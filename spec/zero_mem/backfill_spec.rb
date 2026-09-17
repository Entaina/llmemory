# frozen_string_literal: true

RSpec.describe Llmemory::ZeroMem::Backfill do
  let(:storage) { Llmemory::ZeroMem::Storages::Memory.new }
  let(:user_id) { "u_bf" }
  let(:session_id) { "s_bf" }

  it "creates traces for live checkpoint messages only" do
    messages = [
      { role: :user, content: "still here" },
      { role: :assistant, content: "ack" }
    ]
    result = described_class.new(storage: storage).run!(
      user_id: user_id,
      session_id: session_id,
      messages: messages
    )
    expect(result[:created_trace_ids].size).to eq(2)
    expect(result[:warning]).to include("cannot be reconstructed")
    expect(storage.list_traces(user_id).map(&:content)).to eq(["still here", "ack"])
  end

  it "does not duplicate on repeated backfill with same content keys" do
    messages = [{ role: :user, content: "still here" }]
    backfill = described_class.new(storage: storage)
    backfill.run!(user_id: user_id, session_id: session_id, messages: messages)
    backfill.run!(user_id: user_id, session_id: session_id, messages: messages)
    expect(storage.list_traces(user_id).size).to eq(1)
  end
end
