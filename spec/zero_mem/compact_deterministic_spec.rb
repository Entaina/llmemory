# frozen_string_literal: true

RSpec.describe Llmemory::Memory, "deterministic compact with traces" do
  let(:user_id) { "u_compact" }
  let(:session_id) { "s_compact" }
  let(:trace_store) { Llmemory::ZeroMem::Storages::Memory.new }

  before do
    allow(Llmemory.configuration).to receive(:memory_flush_enabled).and_return(false)
    allow(Llmemory.configuration).to receive(:compact_max_bytes).and_return(40)
  end

  after { Llmemory.reset_configuration! }

  it "does not call the LLM and preserves full text in trace storage" do
    llm = BombLLM.new
    long_term = Llmemory::LongTerm::FileBased::Memory.new(
      user_id: user_id,
      storage: Llmemory::LongTerm::FileBased::Storages::MemoryStorage.new,
      llm: llm
    )
    memory = described_class.new(
      user_id: user_id,
      session_id: session_id,
      trace_store: trace_store,
      long_term: long_term
    )

    memory.add_message(role: :user, content: "AAAAAAAAAA")
    memory.add_message(role: :assistant, content: "BBBBBBBBBB")
    memory.add_message(role: :user, content: "CCCCCCCCCC")

    expect { memory.compact! }.not_to raise_error
    joined = trace_store.list_traces(user_id).map(&:content).join
    expect(joined).to include("AAAAAAAAAA", "BBBBBBBBBB", "CCCCCCCCCC")
    expect(memory.messages.map { |m| m[:content] }).not_to include(a_string_including("AAAAAAAAAA"))
  end
end
