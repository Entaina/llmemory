# frozen_string_literal: true

RSpec.describe Llmemory::ZeroMem::EntityIndex do
  let(:storage) { Llmemory::ZeroMem::Storages::Memory.new }
  let(:index) { described_class.new(storage) }

  it "indexes mentions idempotently per trace content" do
    trace = Llmemory::ZeroMem::Trace.build(
      user_id: "u",
      session_id: "s",
      role: :user,
      content: "Project Atlas uses Nimbus.",
      sequence: 1
    )
    storage.write_trace(trace)
    stats = index.index_trace(trace)
    expect(stats[:affected_entities]).to be >= 2
    expect(storage.entity_exists?("u", "nimbus")).to be(true)
  end
end
