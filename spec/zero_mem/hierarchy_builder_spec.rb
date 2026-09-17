# frozen_string_literal: true

RSpec.describe Llmemory::ZeroMem::HierarchyBuilder do
  let(:storage) { Llmemory::ZeroMem::Storages::Memory.new }
  let(:builder) { described_class.new(storage) }

  def write_trace(user_id:, session_id:, sequence:, content:)
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

  it "creates turn and tail window units" do
    trace = write_trace(user_id: "u", session_id: "s", sequence: 1, content: "hello")
    affected = builder.index_trace(trace, index_version: 1)
    expect(affected).to be >= 2
    kinds = storage.list_units("u").map(&:kind)
    expect(kinds).to include(:turn, :window, :episode)
  end

  it "does not rewrite old windows when indexing a new tail trace" do
    1.upto(10) do |seq|
      t = write_trace(user_id: "u2", session_id: "s2", sequence: seq, content: "msg #{seq}")
      builder.index_trace(t, index_version: seq)
    end
    old_window = storage.list_units("u2", kind: :window).find { |w| w.end_sequence == 9 }
    old_version = old_window.index_version

    t11 = write_trace(user_id: "u2", session_id: "s2", sequence: 11, content: "msg 11")
    builder.index_trace(t11, index_version: 11)

    expect(storage.get_unit("u2", old_window.id).index_version).to eq(old_version)
    expect(storage.list_units("u2", kind: :window).any? { |w| w.end_sequence == 11 }).to be(true)
  end
end
