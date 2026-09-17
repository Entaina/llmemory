# frozen_string_literal: true

require_relative "../retrieval/bm25_scorer"

module Llmemory
  module ZeroMem
    class Engine
      def initialize(trace_store:, user_id:, config: nil, profiler: nil, retriever: nil,
                     graph_retriever: nil, calibrator: nil, assembler: nil, entity_index: nil,
                     embedding_provider: nil, router: nil, fusion: nil, closure: nil, **options)
        if options.key?(:llm) || options.key?("llm")
          raise ArgumentError, "ZeroMem::Engine does not accept an llm client"
        end

        @storage = trace_store
        @user_id = user_id
        @config = config || Llmemory.configuration
        @profiler = profiler || QueryProfiler.new
        @retriever = retriever || HierarchyRetriever.new(@storage, config: @config)
        @entity_index = entity_index || EntityIndex.new(@storage)
        @embedding_provider = embedding_provider
        @graph_retriever = graph_retriever || GraphRetriever.new(
          @storage,
          entity_index: @entity_index,
          embedding_provider: @embedding_provider,
          config: @config
        )
        @calibrator = calibrator || EvidenceCalibrator.new(@storage)
        @assembler = assembler || BudgetAssembler.new
        @router = router || Router.new
        @fusion = fusion || EvidenceFusion.new
        @closure = closure || EvidenceClosure.new(@storage, config: @config)
        @bm25 = Retrieval::Bm25Scorer.new
      end

      def retrieve_evidence(query, top_k: nil, max_tokens: nil, boundary: nil, explain: false,
                            current_trace_id: nil, skip_closure: false, skip_calibration: false,
                            fusion_weights: nil)
        effective_k = effective_top_k(top_k, nil)
        metrics = { llm_calls: 0, encoder_calls: 0, encoder_duration_ms: 0.0, stages: {} }

        profile = nil
        Llmemory::Instrumentation.instrument(:zero_mem_profile, user_id: @user_id, query_chars: query.to_s.length) do
          profile = @profiler.profile(query, boundary: boundary)
        end
        effective_k = effective_top_k(top_k, profile)

        retrieval = nil
        Llmemory::Instrumentation.instrument(:zero_mem_hierarchy_retrieve, user_id: @user_id, workload: profile.workload_class) do
          retrieval = @retriever.retrieve(user_id: @user_id, query: query, profile: profile, top_k: effective_k)
        end

        graph = nil
        Llmemory::Instrumentation.instrument(:zero_mem_graph_retrieve, user_id: @user_id) do
          graph = @graph_retriever.retrieve(user_id: @user_id, query: query, profile: profile, top_k: effective_k)
        end

        degraded = (retrieval[:degraded] + graph[:degraded]).uniq
        degraded << :dense unless @embedding_provider
        degraded.uniq!

        hierarchy_scores = hierarchy_trace_scores(query, retrieval[:traces])
        graph_scores = graph[:trace_scores] || {}
        routing = @router.route(profile, hierarchy_scores: hierarchy_scores, graph_scores: graph_scores, config: @config)
        weights = fusion_weights || routing[:weights]

        fused = @fusion.fuse(graph_scores: graph_scores, hierarchy_scores: hierarchy_scores, weights: weights)
        seed_rows = fused.first(effective_k)
        seed_ids = seed_rows.map { |r| r[:trace_id] }

        closure_result = if skip_closure
                           { seed_trace_ids: seed_ids, closure_trace_ids: [], bridges: [], atomic_groups: [] }
                         else
                           Llmemory::Instrumentation.instrument(:zero_mem_closure, user_id: @user_id, seeds: seed_ids.size) do
                             @closure.expand(
                               user_id: @user_id,
                               profile: profile,
                               seed_trace_ids: seed_ids,
                               fused_ranking: fused
                             )
                           end
                         end

        ordered_ids = (seed_ids + closure_result[:closure_trace_ids]).uniq
        traces = ordered_ids.map { |id| @storage.get_trace(@user_id, id) }.compact

        calibration = if skip_calibration
                        { traces: traces, excluded: [], conflict_trace_ids: [], seed_ids: seed_ids,
                          closure_ids: closure_result[:closure_trace_ids] }
                      else
                        Llmemory::Instrumentation.instrument(:zero_mem_calibrate, user_id: @user_id, trace_count: traces.size) do
                          @calibrator.calibrate(
                            user_id: @user_id,
                            traces: traces,
                            profile: profile,
                            current_trace_id: current_trace_id,
                            fusion_rows: fused,
                            seed_ids: seed_ids,
                            closure_ids: closure_result[:closure_trace_ids]
                          )
                        end
                      end

        fusion_by_id = fused.each_with_object({}) { |row, acc| acc[row[:trace_id].to_s] = row }
        conflict_ids = calibration[:conflict_trace_ids].to_h { |id| [id.to_s, true] }

        evidence = calibration[:traces].map do |trace|
          row = fusion_by_id[trace.id]
          score = row ? row[:final] : 0.5
          Evidence.new(
            trace_id: trace.id,
            content: trace.content,
            role: trace.role,
            session_id: trace.session_id,
            occurred_at: trace.occurred_at,
            confidence: score.clamp(0.0, 1.0),
            score: score.clamp(0.0, 1.0),
            sources: row ? row[:sources] : [],
            conflict: conflict_ids[trace.id] == true,
            seed: seed_ids.include?(trace.id),
            closure: closure_result[:closure_trace_ids].include?(trace.id),
            content_sha256: trace.content_sha256
          )
        end

        seed_evidence = evidence.select(&:seed)
        closure_evidence = evidence.select(&:closure)

        packed = @assembler.assemble(
          evidence,
          max_tokens: max_tokens,
          atomic_groups: closure_result[:atomic_groups]
        )

        explain_payload = if explain
                              build_explain(
                                profile: profile,
                                routing: routing,
                                weights: weights,
                                effective_k: effective_k,
                                graph: graph,
                                retrieval: retrieval,
                                fused: fused,
                                calibration: calibration,
                                closure_result: closure_result,
                                degraded: degraded,
                                warnings: graph[:warnings]
                              )
                            end

        result = EvidenceSet.new(
          route: routing[:route],
          profile: profile,
          evidence: packed,
          seed_evidence: seed_evidence.select { |ev| packed.any? { |p| p.trace_id == ev.trace_id } },
          closure_evidence: closure_evidence.select { |ev| packed.any? { |p| p.trace_id == ev.trace_id } },
          metrics: metrics.merge(
            degraded: degraded,
            seed_recall: seed_evidence.map(&:trace_id),
            closure_recall: (seed_evidence + closure_evidence).map(&:trace_id).uniq
          ),
          explain: explain_payload,
          degraded: degraded,
          relational_trace_scores: graph_scores,
          hierarchy_traces: retrieval[:traces],
          relational_traces: graph[:traces],
          warnings: graph[:warnings]
        )

        Llmemory::Instrumentation.instrument(
          :zero_mem_retrieve,
          user_id: @user_id,
          evidence_count: packed.size,
          degraded: degraded,
          seed_count: seed_evidence.size,
          closure_count: closure_evidence.size
        )

        result
      end

      def to_context(query, **opts)
        retrieve_evidence(query, **opts).to_context
      end

      private

      def effective_top_k(explicit, profile)
        base = explicit || @config.zero_mem_top_k
        need = profile ? [base, profile.expected_evidence_count].max : base
        [need, @config.zero_mem_max_top_k].min
      end

      def hierarchy_trace_scores(query, traces)
        docs = traces.map { |t| { id: t.id, text: t.content } }
        return {} if docs.empty?

        @bm25.score_documents(query, docs).to_h { |d| [d[:id], d[:normalized_bm25].to_f] }
      end

      def build_explain(profile:, routing:, weights:, effective_k:, graph:, retrieval:, fused:,
                        calibration:, closure_result:, degraded:, warnings:)
        {
          profile: profile.to_h,
          route: routing[:route],
          weights: weights,
          thresholds: {
            rho: routing[:rho],
            gamma: @config.zero_mem_pagerank_damping,
            top_k: effective_k
          },
          graph: {
            seeds: graph[:trace_scores]&.keys&.first(5),
            nodes_visited: graph[:traces]&.size,
            truncated: warnings.include?(:pagerank_truncated),
            boosts: []
          },
          hierarchy: {
            episodes: retrieval[:stage_scores][:episodes],
            windows: retrieval[:stage_scores][:windows],
            turns: retrieval[:stage_scores][:turns]
          },
          fusion: {
            per_trace: fused.first(effective_k).map do |row|
              {
                id: row[:trace_id],
                graph: row[:graph],
                hierarchy: row[:hierarchy],
                final: row[:final],
                sources: row[:sources]
              }
            end
          },
          included: calibration[:traces].map(&:id),
          excluded: calibration[:excluded],
          closure: {
            seed_ids: closure_result[:seed_trace_ids],
            closure_ids: closure_result[:closure_trace_ids],
            bridges: closure_result[:bridges]
          },
          warnings: warnings,
          degraded: degraded
        }
      end
    end
  end
end
