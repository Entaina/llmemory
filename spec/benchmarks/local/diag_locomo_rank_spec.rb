# frozen_string_literal: true

require File.expand_path("../../../benchmarks/zero_mem/harness", __dir__)

RSpec.describe "LoCoMo-style temporal localization (diag_locomo regression)" do
  let(:storage) { Llmemory::ZeroMem::Storages::Memory.new }

  def build_caroline_conversation
    turns = []
    turns << {
      "id" => "D1:3",
      "role" => "user",
      "content" => "Caroline went to the LGBTQ support group on Monday 8 May 2023.",
      "occurred_at" => "2023-05-08T13:56:00Z"
    }
    30.times do |i|
      turns << {
        "id" => "D18:#{i}",
        "role" => "assistant",
        "content" => "Caroline mentioned something unrelated in a later session, topic #{i}.",
        "occurred_at" => "2023-09-#{format('%02d', (i % 28) + 1)}T10:00:00Z"
      }
    end
    {
      "id" => "caroline-temporal",
      "sessions" => [{ "id" => "session_1", "turns" => turns }],
      "queries" => [{
        "text" => "When did Caroline go to the LGBTQ support group?",
        "gold_trace_ids" => ["D1:3"],
        "gold_answer" => "8 May 2023"
      }]
    }
  end

  it "ranks gold turn D1:3 in the top 5 for zero_mem retrieval" do
    conv = build_caroline_conversation
    user_id = "diag_locomo_user"
    memory = Llmemory::Memory.new(
      user_id: user_id,
      session_id: "s1",
      trace_store: storage,
      memory_mode: :zero_mem
    )
    turn_to_trace = {}
    conv["sessions"].each do |session|
      session["turns"].each do |turn|
        trace_id = memory.record_trace(
          role: turn["role"],
          content: turn["content"],
          occurred_at: Time.parse(turn["occurred_at"]),
          idempotency_key: turn["id"],
          add_to_checkpoint: false
        )
        turn_to_trace[turn["id"]] = trace_id
      end
    end

    query = conv["queries"].first
    evidence = memory.retrieve_evidence(query["text"], top_k: 10)
    trace_to_turn = turn_to_trace.invert
    ranked_turn_ids = evidence.evidence.map(&:trace_id).filter_map { |tid| trace_to_turn[tid] }
    expect(ranked_turn_ids.first(5)).to include("D1:3")
  end
end
