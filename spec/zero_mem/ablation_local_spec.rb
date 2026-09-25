# frozen_string_literal: true

RSpec.describe "Zero-Mem local ablation" do
  let(:storage) { Llmemory::ZeroMem::Storages::Memory.new }

  def hydrate(conversation_id)
    conv = ZeroMem::FixtureLoader.load_conversation_by_id(conversation_id)
    user_id = "ablation_#{conversation_id}"
    memory = Llmemory::Memory.new(
      user_id: user_id,
      session_id: "s1",
      trace_store: storage,
      memory_mode: :hybrid
    )
    turn_to_trace = {}
    Array(conv["sessions"]).each do |session|
      Array(session["turns"]).each do |turn|
        tid = memory.record_trace(
          role: turn["role"],
          content: turn["content"],
          occurred_at: Time.parse(turn["occurred_at"]),
          idempotency_key: turn["id"],
          add_to_checkpoint: false
        )
        turn_to_trace[turn["id"]] = tid
      end
    end
    [memory, conv, turn_to_trace]
  end

  def recall(memory, query, gold_turn_ids, turn_map, k: 5, **opts)
    result = memory.retrieve_evidence(query["text"], top_k: k, **opts)
    gold_trace_ids = Array(gold_turn_ids).map { |id| turn_map[id] }
    result.recall_at_k(gold_trace_ids, k: k)[:recall]
  end

  it "full pipeline recall is at least each single-view ablation on local fixtures" do
    ZeroMem::FixtureLoader.validate_coverage!
    queries = ZeroMem::FixtureLoader.all_queries.select do |q|
      q["gold_trace_ids"]&.any?
    end

    expect(queries).not_to be_empty

    worse = []
    queries.first(12).each do |query|
      memory, _conv, turn_map = hydrate(query["conversation_id"])
      gold = query["gold_trace_ids"]
      full = recall(memory, query, gold, turn_map)
      hierarchy_only = recall(
        memory, query, gold, turn_map,
        fusion_weights: { graph: 0.0, hierarchy: 1.0 }
      )
      graph_only = recall(
        memory, query, gold, turn_map,
        fusion_weights: { graph: 1.0, hierarchy: 0.0 }
      )
      no_closure = recall(memory, query, gold, turn_map, skip_closure: true)

      worse << query["id"] if full < hierarchy_only || full < graph_only || full < no_closure
    end

    expect(worse).to be_empty
  end
end
