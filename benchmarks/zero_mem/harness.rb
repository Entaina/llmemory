# frozen_string_literal: true

require "llmemory"
require_relative "metrics"
require_relative "reader"
require_relative "variants"
require "json"
require File.expand_path("../local/scorers/date_normalizer", __dir__)
require File.expand_path("../local/bench_trace", __dir__)

# Load fixture helpers from spec support (benchmark-only; not part of the gem).
require File.expand_path("../../spec/support/zero_mem/fixture_loader", __dir__)

module ZeroMemBenchmark
  class Harness
    RECALL_KS = [1, 5, 10].freeze

    def initialize(variant: :classic, llm: nil, reader: nil, retrieve_opts: {})
      @variant = variant.to_sym
      @variant_opts = Variants.fetch(@variant)
      @llm = llm
      @reader = reader || Reader.new
      @retrieve_opts = retrieve_opts
      @results = []
      @turn_to_trace = {}
    end

    def run!(conversations: ZeroMem::FixtureLoader.validate_coverage!)
      conversations.each do |conversation|
        run_conversation(conversation)
      end
      aggregate
    end

    def run_conversation(conversation)
      memory = build_memory(conversation)
      assert_variant_memory_mode!(memory)
      hydrate!(memory, conversation)
      consolidate_if_needed!(memory, conversation)

      turns = ZeroMem::FixtureLoader.turns_by_id(conversation)
      Array(conversation["queries"]).each do |query|
        @results << evaluate_query(memory, conversation, query, turns)
      end
    end

    private

    def build_memory(conversation)
      raise ArgumentError, "Unknown variant #{@variant}" unless Variants.keys.include?(@variant)

      llm = @llm || classic_llm_stub(conversation)
      user_id = "zm0_#{conversation['id']}"
      case @variant_opts[:mode]
      when :zero_mem
        trace_store = Llmemory::ZeroMem::Storages::Memory.new
        Llmemory::Memory.new(
          user_id: user_id,
          session_id: "zm0_session",
          trace_store: trace_store,
          memory_mode: :zero_mem
        )
      when :hybrid
        trace_store = Llmemory::ZeroMem::Storages::Memory.new
        storage = Llmemory::LongTerm::FileBased::Storages::MemoryStorage.new
        long_term = Llmemory::LongTerm::FileBased::Memory.new(
          user_id: user_id,
          storage: storage,
          llm: llm
        )
        Llmemory::Memory.new(
          user_id: user_id,
          session_id: "zm0_session",
          trace_store: trace_store,
          memory_mode: :hybrid,
          long_term: long_term,
          retrieval_engine: Llmemory::Retrieval::Engine.new(long_term, llm: llm)
        )
      else
        storage = Llmemory::LongTerm::FileBased::Storages::MemoryStorage.new
        long_term = Llmemory::LongTerm::FileBased::Memory.new(
          user_id: user_id,
          storage: storage,
          llm: llm
        )
        Llmemory::Memory.new(
          user_id: user_id,
          session_id: "zm0_session",
          memory_mode: :classic,
          long_term: long_term,
          retrieval_engine: Llmemory::Retrieval::Engine.new(long_term, llm: llm)
        )
      end
    end

    def assert_variant_memory_mode!(memory)
      expected = @variant_opts[:mode]
      actual = memory.memory_mode
      return if actual == expected

      raise ArgumentError, "variant #{@variant} expected memory_mode #{expected.inspect}, got #{actual.inspect}"
    end

    def zero_mem_variant?
      @variant_opts[:mode] == :zero_mem
    end

    def hybrid_variant?
      @variant_opts[:mode] == :hybrid
    end

    def trace_ingest_variant?
      zero_mem_variant? || hybrid_variant?
    end

    def classic_llm_stub(conversation)
      facts_by_turn = {}
      ZeroMem::FixtureLoader.turns_by_id(conversation).each do |id, turn|
        facts_by_turn[id] = turn["content"]
      end

      double = Object.new
      double.define_singleton_method(:invoke) do |prompt|
        if prompt.include?("Summarize this user message")
          prompt[/Message: (.+)/m, 1].to_s.strip[0, 200]
        elsif prompt.include?("Extract discrete facts")
          '[]'
        elsif prompt.include?("Memory Synchronization Specialist")
          "# Profile\n"
        elsif prompt.include?("Classify this fact")
          "general"
        else
          "stub"
        end
      end
      double
    end

    def hydrate!(memory, conversation)
      @turn_to_trace = {}
      Array(conversation["sessions"]).each do |session|
        Array(session["turns"]).each do |turn|
          role = (turn["role"] || "user").to_sym
          if trace_ingest_variant?
            trace_id = memory.record_trace(
              role: role,
              content: turn["content"].to_s,
              occurred_at: Llmemory.parse_occurred_at(turn["occurred_at"]),
              idempotency_key: turn["id"],
              add_to_checkpoint: true
            )
            @turn_to_trace[turn["id"]] = trace_id
          else
            memory.add_message(
              role: role,
              content: turn["content"].to_s,
              occurred_at: Llmemory.parse_occurred_at(turn["occurred_at"])
            )
          end
        end
      end
    end

    def consolidate_if_needed!(memory, conversation)
      return unless conversation["consolidate_before_query"] == true

      memory.consolidate!
    end

    def evaluate_query(memory, conversation, query, turns)
      query_text = query["text"].to_s
      qid = query["id"]
      usage_before = memory.llm_usage

      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      retrieve_label = if zero_mem_variant?
                         "retrieve_evidence"
                       elsif @variant_opts[:mode] == :hybrid
                         "retrieve_fused"
                       else
                         "retrieve_classic"
                       end
      if zero_mem_variant?
        evidence = memory.retrieve_evidence(query_text, max_tokens: 2000, **retrieve_kwargs)
        @last_evidence = evidence
        @last_fused = nil
        @last_context = evidence.to_context
      elsif @variant_opts[:mode] == :hybrid
        @last_evidence = nil
        @last_fused = memory.retrieve_fused(query_text, max_tokens: 2000)
        @last_context = @last_fused.to_context
      else
        @last_evidence = nil
        @last_fused = nil
        @last_context = memory.retrieve(query_text, max_tokens: 2000)
      end
      retrieve_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000.0
      usage_after_retrieve = memory.llm_usage

      gold_ids = Array(query["gold_trace_ids"])
      loc = compute_localization(query, turns, gold_ids)

      reader_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      answer_text = @reader.answer(
        question: query_text,
        context: @last_context,
        gold_answer: query["gold_answer"],
        question_type: query["question_type"]
      )
      reader_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - reader_start) * 1000.0

      usage_after = memory.llm_usage
      if LocalBenchmark::BenchTrace.enabled?
        LocalBenchmark::BenchTrace.log(
          "query #{qid} #{retrieve_label} #{retrieve_ms.round(1)}ms " \
          "llm+#{LocalBenchmark::BenchTrace.invoke_calls_delta(usage_before, usage_after_retrieve)} " \
          "embed+#{LocalBenchmark::BenchTrace.embed_calls_delta(usage_before, usage_after_retrieve)}"
        )
        LocalBenchmark::BenchTrace.log(
          "query #{qid} reader #{reader_ms.round(1)}ms " \
          "llm+#{LocalBenchmark::BenchTrace.invoke_calls_delta(usage_after_retrieve, usage_after)}"
        )
      end

      elapsed_ms = retrieve_ms + reader_ms

      answer_metrics = {}
      if query["gold_answer"]
        answer_metrics[:f1] = Metrics.token_f1(answer_text, query["gold_answer"])
        answer_metrics[:bleu1] = Metrics.bleu1(answer_text, query["gold_answer"])
        answer_metrics[:rouge_l] = Metrics.rouge_l(answer_text, query["gold_answer"])
        answer_metrics[:exact_match] = Metrics.exact_match(answer_text, query["gold_answer"])
      end
      answer_metrics[:task_success] = query["task_success"] if query.key?("task_success")

      max_sess = conversation["step_max_sessions"].to_i
      ev_sess = evidence_max_session(query)
      evidence_in_range = max_sess <= 0 || ev_sess <= max_sess

      {
        variant: @variant,
        conversation_id: conversation["id"],
        query_id: query["id"],
        query_text: query_text,
        evidence_max_session: ev_sess,
        evidence_in_range: evidence_in_range,
        language: conversation["language"],
        workload_class: conversation["workload_class"],
        evidence_gap: query["evidence_gap"],
        session_count: query["session_count"] || conversation["session_count"],
        has_revision: query["has_revision"] || conversation["has_revision"],
        category: query["category"],
        question_type: query["question_type"],
        gold_answer: query["gold_answer"],
        prediction: answer_text,
        retrieval_hit: retrieval_hit?(@last_context, query, turns),
        localization: loc,
        answer: answer_metrics,
        cost: {
          invoke_delta: invoke_delta(usage_before, usage_after),
          invoke_calls_delta: calls_delta(usage_before, usage_after, :invoke),
          embed_delta: usage_delta(usage_before, usage_after, :embed),
          latency_ms: elapsed_ms.round(2),
          zero_mem_compliant: zero_mem_variant? ? calls_delta(usage_before, usage_after, :invoke).zero? : nil
        }
      }
    end

    def retrieve_kwargs
      opts = {}
      opts[:fusion_weights] = @variant_opts[:fusion_weights] if @variant_opts[:fusion_weights]
      opts[:skip_closure] = true if @variant_opts[:skip_closure]
      opts[:skip_calibration] = true if @variant_opts[:skip_calibration]
      opts.merge(@retrieve_opts)
    end

    def compute_localization(query, turns, gold_ids)
      return nil if gold_ids.empty?
      return nil if @variant_opts[:mode] == :classic

      ranked_ids = if zero_mem_variant?
                     rank_fixture_turn_ids(@last_evidence, query)
                   elsif @variant_opts[:mode] == :hybrid && @last_fused
                     rank_fused_turn_ids(@last_fused)
                   else
                     rank_trace_ids_in_context(@last_context, turns, query)
                   end

      {
        mrr: Metrics.mrr(ranked_ids, gold_ids),
        ndcg_at_10: Metrics.ndcg_at_k(ranked_ids, gold_ids, 10)
      }.merge(Metrics.recall_at(RECALL_KS, ranked_ids, gold_ids))
    end

    def rank_fixture_turn_ids(evidence, _query)
      return [] unless evidence

      trace_to_turn = @turn_to_trace.invert
      ranked_trace_ids = evidence.evidence.map(&:trace_id)
      ranked_trace_ids.filter_map { |tid| trace_to_turn[tid] }
    end

    def rank_fused_turn_ids(fused)
      trace_to_turn = @turn_to_trace.invert
      fused.ranked_trace_ids.filter_map { |tid| trace_to_turn[tid] }
    end

    def invoke_delta(before, after)
      usage_delta(before, after, :invoke)
    end

    def calls_delta(before, after, key)
      bucket_key = key.to_sym
      after_bucket = (after[bucket_key] || after[bucket_key.to_s] || {})
      before_bucket = (before[bucket_key] || before[bucket_key.to_s] || {})
      (after_bucket[:calls] || after_bucket["calls"] || 0).to_i -
        (before_bucket[:calls] || before_bucket["calls"] || 0).to_i
    end

    def usage_delta(before, after, key)
      bucket_key = key.to_sym
      after_bucket = (after[bucket_key] || after[bucket_key.to_s] || {})
      before_bucket = (before[bucket_key] || before[bucket_key.to_s] || {})
      (after_bucket[:total_tokens] || after_bucket["total_tokens"] || 0).to_i -
        (before_bucket[:total_tokens] || before_bucket["total_tokens"] || 0).to_i
    end

    def evidence_max_session(query)
      Array(query["gold_trace_ids"]).map do |tid|
        m = tid.to_s.match(/\A[Dd](\d+)/)
        m ? m[1].to_i : 999
      end.max || 999
    end

    def retrieval_hit?(context, query, turns)
      ctx = LocalBenchmark::Scorers::DateNormalizer.normalize_text(context)
      gold = LocalBenchmark::Scorers::DateNormalizer.normalize_text(query["gold_answer"])
      return true if !gold.empty? && ctx.include?(gold)

      Array(query["gold_trace_ids"]).any? do |tid|
        content = LocalBenchmark::Scorers::DateNormalizer.normalize_text(turns[tid]&.dig("content"))
        !content.empty? && ctx.include?(content)
      end
    end

    def rank_trace_ids_in_context(context, turns, query)
      text = context.to_s.downcase
      candidates = Array(query["gold_trace_ids"])
      candidates += turns.keys
      candidates.uniq!

      found = candidates.select do |id|
        content = turns[id]&.dig("content").to_s
        !content.empty? && text.include?(content.downcase)
      end

      found.sort_by do |id|
        content = turns[id]["content"].downcase
        text.index(content) || Float::INFINITY
      end
    end

    def aggregate
      return { queries: 0, means: {} } if @results.empty?

      loc_rows = @results.filter_map { |r| r[:localization] }
      loc_means = if loc_rows.empty?
                    {}
                  else
                    keys = loc_rows.first.keys
                    keys.to_h do |key|
                      mean = loc_rows.sum { |r| r[key].to_f } / loc_rows.size
                      [key, mean]
                    end
                  end

      {
        variant: @variant,
        queries: @results.size,
        means: {
          localization: loc_means,
          latency_ms: (@results.sum { |r| r[:cost][:latency_ms] } / @results.size).round(2)
        },
        by_bin: bin_aggregates,
        rows: @results
      }
    end

    def bin_aggregates
      bins = Hash.new { |h, k| h[k] = [] }
      @results.each do |row|
        recall = row[:localization]&.[](:"recall@5")
      bins[[row[:evidence_gap], row[:has_revision]]] << recall unless recall.nil?
      end
      bins.transform_values do |vals|
        { recall_at_5_mean: vals.sum / vals.size }
      end
    end
  end
end
