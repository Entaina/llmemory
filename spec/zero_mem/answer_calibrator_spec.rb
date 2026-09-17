# frozen_string_literal: true

RSpec.describe Llmemory::ZeroMem::AnswerCalibrator do
  let(:calibrator) { described_class.new }

  def evidence(content, trace_id: "tr_1")
    Llmemory::ZeroMem::Evidence.new(
      trace_id: trace_id,
      content: content,
      role: :user,
      session_id: "s1",
      occurred_at: Time.now,
      confidence: 1.0,
      score: 1.0
    )
  end

  def result_for(*contents)
    evs = contents.map.with_index { |c, i| evidence(c, trace_id: "tr_#{i}") }
    Llmemory::ZeroMem::EvidenceSet.new(
      route: :local,
      profile: Llmemory::ZeroMem::QueryProfiler.new.profile("q"),
      evidence: evs,
      metrics: {}
    )
  end

  it "replaces a scalar when exactly one evidence line supports it" do
    res = result_for("Dejo constancia de talla L.")
    out = calibrator.calibrate("Maybe L?", evidence_result: res)
    expect(out[:changed]).to be(true)
    expect(out[:answer]).to eq("L")
  end

  it "does not rewrite free-form answers" do
    res = result_for("context only")
    out = calibrator.calibrate("I think the user prefers blue because of mood.", evidence_result: res)
    expect(out[:changed]).to be(false)
  end

  it "does not replace ambiguous list answers" do
    res = result_for("talla L", "talla M")
    out = calibrator.calibrate("L, M", evidence_result: res)
    expect(out[:changed]).to be(false)
  end
end
