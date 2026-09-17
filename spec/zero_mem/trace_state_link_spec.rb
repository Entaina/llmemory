# frozen_string_literal: true

RSpec.describe "Zero-Mem explicit state links" do
  let(:storage) { Llmemory::ZeroMem::Storages::Memory.new }
  let(:user_id) { "u1" }
  let(:session_id) { "s1" }

  def write_trace(content:, sequence:)
    trace = Llmemory::ZeroMem::Trace.build(
      user_id: user_id,
      session_id: session_id,
      role: :user,
      content: content,
      sequence: sequence
    )
    storage.write_trace(trace)
    trace
  end

  it "closes prior links and resolves current state as-of without last-write-wins on raw traces" do
    t1 = write_trace(content: "addr: Main 1", sequence: 1)
    t2 = write_trace(content: "addr: Central 9", sequence: 2)

    t1_from = Time.parse("2026-01-01T10:00:00Z")
    t2_from = Time.parse("2026-01-02T10:00:00Z")

    storage.write_state_link(
      Llmemory::ZeroMem::TraceStateLink.build(
        user_id: user_id, state_key: "shipping.address", trace_id: t1.id, valid_from: t1_from
      )
    )
    storage.close_open_state_links(user_id, "shipping.address", valid_to: t2_from, except_trace_id: t2.id)
    storage.write_state_link(
      Llmemory::ZeroMem::TraceStateLink.build(
        user_id: user_id,
        state_key: "shipping.address",
        trace_id: t2.id,
        valid_from: t2_from,
        supersedes_trace_id: t1.id
      )
    )

    expect(storage.current_state_trace_id(user_id, "shipping.address", as_of: t1_from + 60)).to eq(t1.id)
    expect(storage.current_state_trace_id(user_id, "shipping.address", as_of: t2_from + 60)).to eq(t2.id)
    expect(storage.list_traces(user_id).map(&:content)).to include("addr: Main 1", "addr: Central 9")
    expect(storage.state_links_for(user_id, "shipping.address").size).to eq(2)
  end
end
