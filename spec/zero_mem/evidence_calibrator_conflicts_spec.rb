# frozen_string_literal: true

RSpec.describe Llmemory::ZeroMem::EvidenceCalibrator do
  let(:storage) { Llmemory::ZeroMem::Storages::Memory.new }
  let(:calibrator) { described_class.new(storage) }

  def trace(content, seq)
    Llmemory::ZeroMem::Trace.build(
      user_id: "u",
      session_id: "s1",
      role: :user,
      content: content,
      sequence: seq
    )
  end

  it "keeps contradictory size facts with conflict markers" do
    t1 = trace("Mi talla es M.", 1)
    t3 = trace("En realidad mi talla es L.", 3)
    [t1, t3].each { |t| storage.write_trace(t) }
    profile = Llmemory::ZeroMem::QueryProfiler.new.profile("¿Cuál es mi talla?")

    result = calibrator.calibrate(user_id: "u", traces: [t1, t3], profile: profile)
    expect(result[:traces].map(&:id)).to contain_exactly(t1.id, t3.id)
    expect(result[:conflict_trace_ids]).to contain_exactly(t1.id, t3.id)
  end

  it "does not last-write-win when both conflict traces remain" do
    t1 = trace("Mi talla es M.", 1)
    t3 = trace("En realidad mi talla es L.", 3)
    result = calibrator.calibrate(
      user_id: "u",
      traces: [t1, t3],
      profile: Llmemory::ZeroMem::QueryProfiler.new.profile("talla")
    )
    expect(result[:traces].size).to eq(2)
  end
end
