# frozen_string_literal: true

RSpec.describe Llmemory::ZeroMem::EvidenceClosure do
  let(:storage) { Llmemory::ZeroMem::Storages::Memory.new }
  let(:closure) { described_class.new(storage) }

  def write(user_id, session_id, content, seq)
    trace = Llmemory::ZeroMem::Trace.build(
      user_id: user_id,
      session_id: session_id,
      role: :user,
      content: content,
      sequence: seq
    )
    storage.write_trace(trace)
    prev = storage.previous_trace(user_id, session_id, seq)
    storage.link_adjacent_traces(user_id, prev.id, trace.id) if prev
    trace
  end

  it "adds adjacent bridge traces without leaving the session boundary" do
    user_id = "u_close"
    t1 = write(user_id, "s1", "seed one", 1)
    t2 = write(user_id, "s1", "bridge turn", 2)
    write(user_id, "s2", "other session", 1)

    profile = Llmemory::ZeroMem::QueryProfiler.new.profile("seed", boundary: { session_id: "s1" })
    result = closure.expand(
      user_id: user_id,
      profile: profile,
      seed_trace_ids: [t1.id],
      fused_ranking: [{ trace_id: t1.id, final: 1.0 }]
    )

    expect(result[:closure_trace_ids]).to include(t2.id)
    other = storage.get_trace(user_id, result[:closure_trace_ids].first)
    expect(other.session_id).to eq("s1")
  end

  it "deduplicates closure ids" do
    user_id = "u_dedup"
    t1 = write(user_id, "s1", "a", 1)
    t2 = write(user_id, "s1", "b", 2)
    profile = Llmemory::ZeroMem::QueryProfiler.new.profile("a")
    result = closure.expand(
      user_id: user_id,
      profile: profile,
      seed_trace_ids: [t1.id, t2.id],
      fused_ranking: []
    )
    expect(result[:closure_trace_ids].uniq.size).to eq(result[:closure_trace_ids].size)
  end
end
