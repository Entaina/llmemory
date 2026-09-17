# frozen_string_literal: true

require File.expand_path("../zero_mem/harness", __dir__)
require_relative "tool_call_reader"

module LocalBenchmark
  class Harness < ZeroMemBenchmark::Harness
    def run_conversation(conversation)
      memory = build_memory(conversation)
      mode = conversation["consolidate_mode"].to_s
      if !zero_mem_variant? && mode == "per_session"
        hydrate_and_consolidate_per_session!(memory, conversation)
      else
        hydrate!(memory, conversation)
        consolidate_if_needed!(memory, conversation)
        consolidate_after_hydrate!(memory, conversation)
      end

      turns = ZeroMem::FixtureLoader.turns_by_id(conversation)
      Array(conversation["queries"]).each do |query|
        row = evaluate_query(memory, conversation, query, turns)
        @results << row
        persist_subtask_answer!(memory, conversation, row)
      end
    end

    def evaluate_query(memory, conversation, query, turns)
      reader = @reader
      @reader = ToolCallReader.new.to_reader_for_query(query) if query["question_type"] == "tool_call"
      row = super
      @reader = reader
      row[:metadata] = query["metadata"] if query["metadata"]
      row
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
      Array(conversation["sessions"]).each do |session|
        Array(session["turns"]).each do |turn|
          ingest_turn!(memory, turn)
        end
        next if zero_mem_variant?

        memory.consolidate!
        memory.clear_session!
      end
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
