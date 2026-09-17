# frozen_string_literal: true

RSpec.describe "Zero-Mem TTL and archive cascade" do
  let(:storage) { Llmemory::ZeroMem::Storages::Memory.new }
  let(:user_id) { "u_ttl" }

  it "removes mentions and entity links when a trace is archived" do
    trace = Llmemory::ZeroMem::Trace.build(
      user_id: user_id,
      session_id: "s1",
      role: :user,
      content: "Atlas project",
      sequence: 1
    )
    storage.write_trace(trace)
    Llmemory::ZeroMem::EntityIndex.new(storage).index_trace(trace)

    storage.archive_trace(user_id, trace.id)
    expect(storage.trace_ids_for_entity_key(user_id, "atlas")).to be_empty
    expect(storage.list_units(user_id)).to be_empty
  end

  it "archives old traces via ZeroMemTTL" do
    Llmemory.configure { |c| c.zero_mem_ttl_days = 1 }
    old = Llmemory::ZeroMem::Trace.build(
      user_id: user_id,
      session_id: "s1",
      role: :user,
      content: "old",
      sequence: 1,
      occurred_at: Time.now - (2 * 86_400)
    )
    storage.write_trace(old)
    report = Llmemory::Maintenance::ZeroMemTTL.new(storage: storage, ttl_days: 1).run!(user_id: user_id)
    expect(report[:archived]).to eq(1)
    expect(storage.list_traces(user_id)).to be_empty
  ensure
    Llmemory.reset_configuration!
  end
end
