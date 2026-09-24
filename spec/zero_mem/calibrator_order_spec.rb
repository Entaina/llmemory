# frozen_string_literal: true

RSpec.describe Llmemory::ZeroMem::EvidenceCalibrator do
  let(:storage) { Llmemory::ZeroMem::Storages::Memory.new }
  let(:calibrator) { described_class.new(storage) }
  let(:user_id) { "cal_user" }
  let(:profile) do
    Llmemory::ZeroMem::QueryProfiler.new.profile("When did Caroline go to the LGBTQ support group?")
  end

  def build_trace(id:, content:, occurred_at:)
    Llmemory::ZeroMem::Trace.build(
      id: id,
      user_id: user_id,
      session_id: "s1",
      role: "user",
      content: content,
      sequence: id.hash.abs % 10_000,
      occurred_at: occurred_at
    ).tap { |t| storage.write_trace(t) }
  end

  it "orders temporal queries by fusion score, not newest occurred_at" do
    old_gold = build_trace(
      id: "t_gold",
      content: "Caroline went to the LGBTQ support group yesterday and it was powerful.",
      occurred_at: Time.utc(2023, 5, 8)
    )
    recent_filler = build_trace(
      id: "t_recent",
      content: "Caroline mentioned something unrelated in a later session.",
      occurred_at: Time.utc(2023, 10, 20)
    )
    fusion_rows = [
      { trace_id: "t_gold", final: 0.85 },
      { trace_id: "t_recent", final: 0.12 }
    ]

    result = calibrator.calibrate(
      user_id: user_id,
      traces: [recent_filler, old_gold],
      profile: profile,
      fusion_rows: fusion_rows
    )

    expect(result[:traces].first.id).to eq("t_gold")
  end
end
