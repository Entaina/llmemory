# frozen_string_literal: true

RSpec.describe Llmemory::ZeroMem::Repair do
  let(:storage) { Llmemory::ZeroMem::Storages::Memory.new }
  let(:user_id) { "u_rep" }
  let(:session_id) { "s_rep" }

  it "aligns watermark with persisted traces after checkpoint drift" do
    trace = Llmemory::ZeroMem::Trace.build(
      user_id: user_id,
      session_id: session_id,
      role: :user,
      content: "persisted",
      sequence: 1
    )
    storage.write_trace(trace)

    report = described_class.new(storage: storage).run!(
      user_id: user_id,
      session_id: session_id,
      checkpoint_messages: []
    )

    expect(report[:trace_count]).to eq(1)
    expect(report[:checkpoint_message_count]).to eq(0)
    expect(report[:last_sequence]).to eq(1)
  end
end
