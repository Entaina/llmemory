# frozen_string_literal: true

require File.expand_path("../zero_mem/harness", __dir__)
require_relative "tool_call_reader"
require_relative "bench_trace"

module LocalBenchmark
  class Harness < ZeroMemBenchmark::Harness
    def run_conversation(conversation)
      memory = BenchTrace.measure("build_memory #{conversation['id']}") { build_memory(conversation) }
      assert_variant_memory_mode!(memory)
      mode = conversation["consolidate_mode"].to_s
      if !zero_mem_variant? && mode == "per_session"
        hydrate_and_consolidate_per_session!(memory, conversation)
      else
        BenchTrace.measure("hydrate #{conversation['id']}") { hydrate!(memory, conversation) }
        BenchTrace.measure("consolidate_if_needed") { consolidate_if_needed!(memory, conversation) }
        BenchTrace.measure("consolidate_after_hydrate") { consolidate_after_hydrate!(memory, conversation) }
      end

      turns = ZeroMem::FixtureLoader.turns_by_id(conversation)
      Array(conversation["queries"]).each do |query|
        row = evaluate_query(memory, conversation, query, turns)
        @results << row
        persist_subtask_answer!(memory, conversation, row)
      end

      stats = snapshot_memory_stats(memory)
      return unless stats

      qcount = Array(conversation["queries"]).size
      @results.last(qcount).each { |r| r[:memory_stats] = stats }
    end

    def evaluate_query(memory, conversation, query, turns)
      reader = @reader
      if query["question_type"] == "tool_call"
        @reader = ToolCallReader.new.to_reader_for_query(query)
      elsif query["question_type"] == "locomo_plus_continuation"
        @reader = ReaderLLM.new(mode: :continuation).to_reader
      end
      row = super
      @reader = reader
      row[:metadata] = query["metadata"] if query["metadata"]
      attach_debug_artifacts!(row, memory)
      row
    end

    def attach_debug_artifacts!(row, memory)
      limit = ENV.fetch("LLMEMORY_BENCH_CONTEXT_CHARS", "4000").to_i
      ctx = @last_context.to_s
      row[:context] = ctx.length > limit ? "#{ctx[0, limit]}..." : ctx
      row[:ranked_trace_ids] = ranked_trace_ids_for_artifacts
      row[:fused_items] = fused_items_for_artifacts
    end

    def ranked_trace_ids_for_artifacts
      if @last_fused
        @last_fused.ranked_trace_ids
      elsif @last_evidence
        @last_evidence.evidence.map(&:trace_id)
      else
        []
      end
    end

    def fused_items_for_artifacts
      return [] unless @last_fused

      @last_fused.items.map do |item|
        {
          kind: item[:kind],
          id: item[:id] || item[:trace_id],
          score: item[:score]
        }
      end
    end

    def snapshot_memory_stats(memory)
      lt = memory.instance_variable_get(:@long_term)
      return nil unless lt.respond_to?(:stats)

      lt.stats
    rescue StandardError
      nil
    end

    def persist_subtask_answer!(memory, conversation, row)
      return unless conversation["persist_subtask_answers"] == true

      prediction = row[:prediction].to_s
      return if prediction.empty?

      memory.add_message(role: :assistant, content: prediction)
    end

    private

    def consolidate_after_hydrate!(memory, conversation)
      return if zero_mem_variant?
      return unless conversation["consolidate_after_hydrate"] == true

      memory.consolidate!
    end

    # Long benchmarks (LoCoMo): one consolidate! per session, then clear short-term checkpoint
    # so the LLM never sees the full multi-session transcript at once.
    def hydrate_and_consolidate_per_session!(memory, conversation)
      @turn_to_trace = {} if trace_ingest_variant?
      sessions = sessions_for_hydrate(conversation)
      BenchTrace.log(
        "hydrate_per_session conv=#{conversation['id']} sessions=#{sessions.size}/#{conversation['session_count']} " \
        "queries=#{Array(conversation['queries']).size} variant=#{@variant}"
      )
      sessions.each do |session|
        sid = session["id"]
        turns = Array(session["turns"])
        BenchTrace.measure("  #{sid} ingest #{turns.size} turns") do
          turns.each { |turn| ingest_turn!(memory, turn) }
        end
        next if zero_mem_variant?

        if bench_skip_consolidate?
          BenchTrace.log("  #{sid} skip consolidate! (LLMEMORY_BENCH_SKIP_CONSOLIDATE=1)")
          memory.clear_session!
          next
        end

        usage_before = memory.llm_usage
        t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        memory.consolidate!
        consolidate_ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000.0
        usage_after = memory.llm_usage
        if BenchTrace.enabled?
          inv = BenchTrace.invoke_calls_delta(usage_before, usage_after)
          emb = BenchTrace.embed_calls_delta(usage_before, usage_after)
          BenchTrace.log("  #{sid} consolidate! #{consolidate_ms.round(1)}ms llm_invoke+#{inv} embed+#{emb}")
        end
        memory.clear_session!
      end
    end

    def bench_skip_consolidate?
      ENV["LLMEMORY_BENCH_SKIP_CONSOLIDATE"] == "1" && hybrid_variant?
    end

    def sessions_for_hydrate(conversation)
      sessions = Array(conversation["sessions"])
      cap = conversation["step_max_sessions"].to_i
      cap = ENV["LOCOMO_MAX_SESSIONS"].to_i if cap <= 0
      cap = ENV["STEP_MAX_SESSIONS"].to_i if cap <= 0
      return sessions if cap <= 0

      sessions.first(cap)
    end

    def ingest_turn!(memory, turn)
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
