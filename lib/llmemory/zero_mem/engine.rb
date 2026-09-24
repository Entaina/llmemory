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
          profile = zm_bench_trace("profile") { @profiler.profile(query, boundary: boundary) }
        end
        effective_k = effective_top_k(top_k, profile)

        retrieval = nil
        Llmemory::Instrumentation.instrument(:zero_mem_hierarchy_retrieve, user_id: @user_id, workload: profile.workload_class) do
          retrieval = zm_bench_trace("hierarchy_retrieve") do
            @retriever.retrieve(user_id: @user_id, query: query, profile: profile, top_k: effective_k)
          end
        end

        graph = nil
        Llmemory::Instrumentation.instrument(:zero_mem_graph_retrieve, user_id: @user_id) do
          graph = zm_bench_trace("graph_retrieve") do
            @graph_retriever.retrieve(user_id: @user_id, query: query, profile: profile, top_k: effective_k)
          end
        end

        degraded = (retrieval[:degraded] + graph[:degraded]).uniq
        degraded << :dense unless @embedding_provider
        degraded.uniq!

        seed_traces = seed_hierarchy_traces(retrieval)
        hierarchy_scores = hierarchy_trace_scores(query, seed_traces)
        graph_scores = graph[:trace_scores] || {}
        routing = @router.route(profile, hierarchy_scores: hierarchy_scores, graph_scores: graph_scores, config: @config)
        weights = fusion_weights || routing[:weights]

        fused = @fusion.fuse(graph_scores: graph_scores, hierarchy_scores: hierarchy_scores, weights: weights)
        fused = boost_fusion_rows(fused, query: query, profile: profile)
        seed_rows = reserve_newest_rows(fused.first(effective_k), fused, effective_k)
        seed_ids = seed_rows.map { |r| r[:trace_id] }

        neighbor_ids = Array(retrieval[:neighbor_trace_ids]).map(&:to_s)
        closure_result = if skip_closure
                           {
                             seed_trace_ids: seed_ids,
                             closure_trace_ids: neighbor_ids,
                             bridges: [],
                             atomic_groups: []
                           }
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
        closure_result[:closure_trace_ids] = (neighbor_ids + closure_result[:closure_trace_ids]).uniq

        ordered_ids = (seed_ids + closure_result[:closure_trace_ids]).uniq
        traces = ordered_ids.map { |id| @storage.get_trace(@user_id, id) }.compact

        calibration = if skip_calibration
                        { traces: traces, excluded: [], conflict_trace_ids: [], seed_ids: seed_ids,
                          closure_ids: closure_result[:closure_trace_ids] }
                      else
                        Llmemory::Instrumentation.instrument(:zero_mem_calibrate, user_id: @user_id, trace_count: traces.size) do
                          zm_bench_trace("calibrate(#{traces.size})") do
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
            closure: closure_result[:closure_trace_ids].include?(trace.id) || neighbor_ids.include?(trace.id.to_s),
            content_sha256: trace.content_sha256,
            occurred_at_inferred: trace.metadata[:occurred_at_inferred] == true
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

      def zm_bench_trace(label)
        return yield unless ENV["LLMEMORY_BENCH_TRACE"] == "1"

        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        result = yield
        ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000.0
        line = "[bench-trace zero_mem] #{label} #{ms.round(1)}ms"
        warn line
        path = ENV["LLMEMORY_BENCH_TRACE_FILE"].to_s
        File.open(path, "a") { |f| f.puts line } unless path.empty?
        result
      end

      def effective_top_k(explicit, profile)
        base = explicit || @config.zero_mem_top_k
        need = profile ? [base, profile.expected_evidence_count].max : base
        [need, @config.zero_mem_max_top_k].min
      end

      def reserve_newest_rows(seed_rows, fused, effective_k)
        dated = fused.filter_map do |row|
          at = @storage.get_trace(@user_id, row[:trace_id])&.occurred_at
          [row, at] if at
        end
        return seed_rows if dated.empty?

        newest = dated.sort_by { |_, at| at }.last(2).map(&:first)
        present = seed_rows.map { |row| row[:trace_id].to_s }.to_set
        missing = newest.reject { |row| present.include?(row[:trace_id].to_s) }
        return seed_rows if missing.empty?

        room = [effective_k - missing.size, 0].max
        (seed_rows.first(room) + missing).uniq { |row| row[:trace_id] }
      end

      def seed_hierarchy_traces(retrieval)
        seed_ids = Array(retrieval[:seed_trace_ids]).map(&:to_s).to_set
        return retrieval[:traces] if seed_ids.empty?

        retrieval[:traces].select { |t| seed_ids.include?(t.id.to_s) }
      end

      GREETING_TURN = /\A(?:\w+:\s*)?(?:hi|hey|hello|good to see you|what'?s up|thanks|thank you|wow|cool|nice|great|ok|okay|yep|yeah)[!.?\s]*\z/i

      def boost_fusion_rows(fused, query:, profile:)
        q_tokens = Llmemory::Tokenizer.tokenize(query.to_s).reject { |t| t.length < 3 }.to_set
        temporal = profile.workload_class == :temporal || profile.freshness_requirement
        newest = fused.filter_map { |row| @storage.get_trace(@user_id, row[:trace_id])&.occurred_at }.max
        boosted = fused.map do |row|
          trace = @storage.get_trace(@user_id, row[:trace_id])
          next row unless trace

          down = trace.content.downcase
          bonus = 0.0
          profile.subject_entities.each do |entity|
            bonus += 0.06 if down.include?(entity.downcase)
          end
          bonus += 0.04 * q_tokens.count { |t| down.include?(t) } if q_tokens.any?
          if q_tokens.any? && q_tokens.none? { |t| down.include?(t) }
            bonus -= 0.07
          end
          if temporal && down.match?(/\b(monday|tuesday|wednesday|thursday|friday|saturday|sunday|\d{4}-\d{2}-\d{2}|jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)\b/i)
            bonus += 0.08
          end
          if newest && trace.occurred_at && trace.occurred_at >= newest
            bonus += 0.35
          end
          bonus -= 0.12 if low_information_turn?(down)
          project = trace.metadata[:project] || trace.metadata["project"]
          if project && q_tokens.any? { |t| project.to_s.downcase.include?(t) }
            bonus += 0.1
          end
          row.merge(final: (row[:final].to_f + bonus).clamp(0.0, 1.5))
        end
        boosted.sort_by { |row| [-row[:final], row[:trace_id]] }
      end

      def low_information_turn?(down)
        stripped = down.strip
        return true if stripped.length < 40 && GREETING_TURN.match?(stripped)

        stripped.length < 25
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
