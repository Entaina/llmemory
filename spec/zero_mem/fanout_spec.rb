# frozen_string_literal: true

RSpec.describe "Zero-Mem indexer fan-out" do
  it "keeps maintenance fan-out bounded for a single write in a large corpus" do
    storage = Llmemory::ZeroMem::Storages::Memory.new
    user_id = "u_fan"
    session_id = "s1"
    indexer = Llmemory::ZeroMem::Indexer.new(storage)

    100.times do |i|
      trace = Llmemory::ZeroMem::Trace.build(
        user_id: user_id,
        session_id: session_id,
        role: :user,
        content: "filler message #{i}",
        sequence: i + 1
      )
      storage.write_trace(trace)
      indexer.after_trace_write(trace: trace)
    end

    new_trace = Llmemory::ZeroMem::Trace.build(
      user_id: user_id,
      session_id: session_id,
      role: :user,
      content: "needle target",
      sequence: 101
    )
    storage.write_trace(new_trace)
    stats = indexer.after_trace_write(trace: new_trace)

    expect(stats[:maintenance_fanout]).to be <= 20
    expect(storage.list_traces(user_id).size).to eq(101)
  end
end
