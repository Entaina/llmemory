# frozen_string_literal: true

RSpec.describe Llmemory::ZeroMem::EvidenceSet do
  let(:profile) do
    Llmemory::ZeroMem::QueryProfile.new(
      subject_entities: ["Caroline"],
      keywords: %w[LGBTQ support],
      quoted_phrases: [],
      answer_type: :datetime,
      temporal_cues: ["when"],
      aggregation_cues: [],
      boundary: nil,
      workload_class: :temporal,
      freshness_requirement: true,
      expected_evidence_count: 3,
      language: :en,
      rule_ids: ["temporal_cues"]
    )
  end

  def build_evidence(trace_id:, content:, occurred_at:, inferred: false)
    Llmemory::ZeroMem::Evidence.new(
      trace_id: trace_id,
      content: content,
      role: "user",
      session_id: "s1",
      occurred_at: occurred_at,
      confidence: 0.82,
      score: 0.82,
      sources: [:hierarchy],
      conflict: false,
      seed: true,
      closure: false,
      content_sha256: Digest::SHA256.hexdigest(content),
      occurred_at_inferred: inferred
    )
  end

  it "formats readable dates and marks inferred times as undated" do
    ev = build_evidence(
      trace_id: "t1",
      content: "Caroline attended the LGBTQ support group.",
      occurred_at: Time.utc(2023, 5, 8, 13, 56),
      inferred: false
    )
    undated = build_evidence(
      trace_id: "t2",
      content: "Unrelated filler turn.",
      occurred_at: Time.utc(2026, 1, 1),
      inferred: true
    )
    set = described_class.new(
      route: :local,
      profile: profile,
      evidence: [ev, undated],
      metrics: {}
    )
    ctx = set.to_context
    expect(ctx).to include("Mon 8 May 2023")
    expect(ctx).not_to include("13:56")
    expect(ctx).to include("(undated)")
    expect(ctx).not_to include("2026-01-01")
    expect(ctx).to include("Timeline:")
  end

  it "shows confidence on each line" do
    ev = build_evidence(
      trace_id: "t1",
      content: "Short note.",
      occurred_at: Time.utc(2023, 1, 1),
      inferred: false
    )
    set = described_class.new(route: :local, profile: profile, evidence: [ev], metrics: {})
    expect(set.to_context).to match(/conf=0\.82/)
  end
end
