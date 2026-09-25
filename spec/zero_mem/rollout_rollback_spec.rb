# frozen_string_literal: true

RSpec.describe "trace persistence" do
  let(:trace_store) { Llmemory::ZeroMem::Storages::Memory.new }

  before do
    Llmemory.reset_configuration!
  end

  it "writes traces and retrieves them in fused memory" do
    memory = Llmemory::Memory.new(
      user_id: "u_roll",
      session_id: "s1",
      trace_store: trace_store
    )
    memory.add_message(role: :user, content: "shadow fact")
    expect(trace_store.list_traces("u_roll").size).to eq(1)

    context = memory.retrieve("shadow")
    expect(context).to include("shadow")
    expect(context).not_to include("ZERO-MEM EVIDENCE")
  end

  it "keeps traces readable across instances" do
    memory = Llmemory::Memory.new(
      user_id: "u_rb",
      session_id: "s1",
      trace_store: trace_store
    )
    memory.add_message(role: :user, content: "persisted trace")
    trace_id = trace_store.list_traces("u_rb").first.id

    again = Llmemory::Memory.new(
      user_id: "u_rb",
      session_id: "s1",
      trace_store: trace_store
    )
    expect(again.trace_store.get_trace("u_rb", trace_id)).not_to be_nil
    expect(again.retrieve_evidence("persisted").evidence).not_to be_empty
  end
end
