# frozen_string_literal: true

RSpec.describe Llmemory::ZeroMem::EvidenceCalibrator do
  let(:storage) { Llmemory::ZeroMem::Storages::Memory.new }
  let(:calibrator) { described_class.new(storage) }

  it "drops archived traces and honors boundary" do
    trace = Llmemory::ZeroMem::Trace.build(
      user_id: "u",
      session_id: "s1",
      role: :user,
      content: "secret",
      sequence: 1
    )
    storage.write_trace(trace)
    storage.archive_trace("u", trace.id)
    archived = storage.get_trace("u", trace.id)
    profile = Llmemory::ZeroMem::QueryProfiler.new.profile("secret", boundary: { session_id: "s1" })
    out = calibrator.calibrate(user_id: "u", traces: [archived], profile: profile)
    expect(out[:traces]).to be_empty
    expect(out[:excluded].map { |e| e[:reason] }).to include(:archived)
  end
end
