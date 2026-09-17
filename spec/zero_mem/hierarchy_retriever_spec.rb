# frozen_string_literal: true

RSpec.describe Llmemory::ZeroMem::HierarchyRetriever do
  let(:storage) { Llmemory::ZeroMem::Storages::Memory.new }
  let(:indexer) { Llmemory::ZeroMem::Indexer.new(storage) }
  let(:retriever) { described_class.new(storage) }
  let(:user_id) { "u_ret" }
  let(:session_id) { "s_ret" }

  before do
    memory = Llmemory::Memory.new(user_id: user_id, session_id: session_id, trace_store: storage)
    memory.add_message(role: :user, content: "My favorite color is teal.")
    memory.add_message(role: :assistant, content: "Noted teal.")
  end

  it "returns traces with dense degradation flagged" do
    profile = Llmemory::ZeroMem::QueryProfiler.new.profile("favorite color teal")
    result = retriever.retrieve(user_id: user_id, query: "favorite color teal", profile: profile, top_k: 5)
    expect(result[:traces]).not_to be_empty
    expect(result[:degraded]).to include(:dense)
  end
end
