# frozen_string_literal: true

RSpec.describe Llmemory::Memory, "#record_trace" do
  let(:user_id) { "u_rec" }
  let(:session_id) { "s_rec" }
  let(:trace_store) { Llmemory::ZeroMem::Storages::Memory.new }
  let(:memory) do
    described_class.new(user_id: user_id, session_id: session_id, trace_store: trace_store)
  end

  it "dual-writes checkpoint messages and returns true from add_message" do
    expect(memory.add_message(role: :user, content: "Hola")).to be(true)
    expect(memory.messages.last[:content]).to eq("Hola")
    expect(trace_store.list_traces(user_id).size).to eq(1)
  end

  it "stores optional metadata and idempotency" do
    id1 = memory.record_trace(
      role: :user,
      content: "Ping",
      metadata: { source: "ui" },
      idempotency_key: "msg-1",
      add_to_checkpoint: false
    )
    id2 = memory.record_trace(
      role: :user,
      content: "Ping",
      idempotency_key: "msg-1",
      add_to_checkpoint: false
    )
    expect(id2).to eq(id1)
    expect(trace_store.list_traces(user_id).size).to eq(1)
    trace = trace_store.get_trace(user_id, id1)
    expect(trace.metadata[:source]).to eq("ui")
  end

  it "keeps traces when clear_session! wipes the checkpoint" do
    memory.add_message(role: :user, content: " durable ")
    memory.clear_session!
    expect(memory.messages).to be_empty
    expect(trace_store.list_traces(user_id).map(&:content)).to eq([" durable "])
  end
end
