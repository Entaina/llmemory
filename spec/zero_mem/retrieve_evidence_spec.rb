# frozen_string_literal: true

RSpec.describe "Memory#retrieve_evidence (lexical Zero-Mem)" do
  let(:storage) { Llmemory::ZeroMem::Storages::Memory.new }

  def hydrate_fixture(conversation_id)
    conv = ZeroMem::FixtureLoader.load_conversation_by_id(conversation_id)
    user_id = "zm2_#{conversation_id}"
    session_id = "zm2_session"
    memory = Llmemory::Memory.new(
      user_id: user_id,
      session_id: session_id,
      trace_store: storage,
      memory_mode: :hybrid
    )
    Array(conv["sessions"]).each do |session|
      Array(session["turns"]).each do |turn|
        memory.record_trace(
          role: turn["role"],
          content: turn["content"],
          occurred_at: Time.parse(turn["occurred_at"]),
          add_to_checkpoint: false
        )
      end
    end
    [memory, conv]
  end

  it "resolves trace_ids for ZM0 fixtures without LLM" do
    memory, conv = hydrate_fixture("es_single_hop_01")
    query = conv["queries"].first
    result = memory.retrieve_evidence(query["text"], top_k: 5)
    expect(result.metrics[:llm_calls]).to eq(0)
    expect(result.evidence).not_to be_empty
    result.evidence.each do |ev|
      expect(storage.get_trace(memory.user_id, ev.trace_id)).not_to be_nil
    end
    gold = query["gold_trace_ids"]
    found = result.evidence.map(&:trace_id)
    turns = ZeroMem::FixtureLoader.turns_by_id(conv)
    gold_contents = gold.map { |id| turns[id]["content"].downcase }
    expect(result.to_context.downcase).to include(gold_contents.first)
  end

  it "isolates users" do
    mem_a, = hydrate_fixture("es_single_hop_01")
    mem_b, = hydrate_fixture("en_single_hop_01")
    result = mem_a.retrieve_evidence("color favorito", top_k: 5)
    result.evidence.each do |ev|
      trace = storage.get_trace(mem_a.user_id, ev.trace_id)
      expect(trace.user_id).to eq(mem_a.user_id)
      expect(storage.get_trace(mem_b.user_id, ev.trace_id)).to be_nil
    end
  end
end
