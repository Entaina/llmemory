# frozen_string_literal: true

RSpec.describe Llmemory::Retrieval::HybridFusion do
  subject(:fusion) { described_class.new }

  let(:profile) do
    Llmemory::ZeroMem::QueryProfiler.new.profile(
      "When did Caroline visit the support group?",
      language: :en
    )
  end

  def evidence_row(trace_id:, content:, score:, seed: true, closure: false, occurred_at: Time.utc(2023, 5, 7), occurred_at_inferred: false)
    Llmemory::ZeroMem::Evidence.new(
      trace_id: trace_id,
      content: content,
      role: "user",
      session_id: "s1",
      occurred_at: occurred_at,
      confidence: score,
      score: score,
      seed: seed,
      closure: closure,
      occurred_at_inferred: occurred_at_inferred
    )
  end

  it "boosts facts for local_fact attribute queries" do
    profile_attr = Llmemory::ZeroMem::QueryProfiler.new.profile(
      "What is Caroline's identity?",
      language: :en
    )
    classic = [
      { id: "f1", text: "Caroline is a transgender woman", score: 0.5, temporal_score: 0.5, kind: :fact }
    ]
    evidence_set = Llmemory::ZeroMem::EvidenceSet.new(
      route: :hierarchy,
      profile: profile_attr,
      evidence: [
        evidence_row(trace_id: "t1", content: "The transgender stories were inspiring.", score: 0.9)
      ],
      metrics: {}
    )
    result = fusion.fuse(classic_candidates: classic, evidence_set: evidence_set, max_tokens: 500, skip_resources: true)
    expect(result.items.first[:kind]).to eq(:fact)
  end

  it "ranks a person fact that names the subject above a generic leader fact" do
    profile_who = Llmemory::ZeroMem::QueryProfiler.new.profile("Who was the Norse leader?")
    classic = [
      { id: "f1", text: "Ali Belhadj was a charismatic Islamist young preacher and leader of the FIS", score: 0.9, kind: :fact },
      { id: "f2", text: "The Norse leader was Rollo", score: 0.4, kind: :fact }
    ]
    evidence_set = Llmemory::ZeroMem::EvidenceSet.new(
      route: :hierarchy,
      profile: profile_who,
      evidence: [],
      metrics: {}
    )
    result = fusion.fuse(classic_candidates: classic, evidence_set: evidence_set, max_tokens: 400)
    expect(result.items.first[:text]).to include("Rollo")
  end

  it "ranks corroborated facts above redundant traces for non-temporal slot queries" do
    profile_slot = Llmemory::ZeroMem::QueryProfiler.new.profile(
      "What kayak did the user buy?",
      language: :en
    )
    classic = [
      {
        id: "f1",
        text: "User owns a blue kayak named Nimbus",
        score: 0.9,
        temporal_score: 0.9,
        kind: :fact,
        provenance: { sources: [{ type: "trace", id: "t1" }] }
      }
    ]
    evidence_set = Llmemory::ZeroMem::EvidenceSet.new(
      route: :hierarchy,
      profile: profile_slot,
      evidence: [
        evidence_row(trace_id: "t1", content: "I bought a blue kayak named Nimbus.", score: 0.8)
      ],
      metrics: {}
    )

    result = fusion.fuse(classic_candidates: classic, evidence_set: evidence_set, max_tokens: 500)
    expect(result.items.map { |i| i[:kind] }).to eq([:fact])
    expect(result.to_context).to include("=== MEMORY ===", "Nimbus")
  end

  it "keeps a corroborated trace when the fact drops a named entity" do
    profile_choice = Llmemory::ZeroMem::QueryProfiler.new.profile(
      "Which text summarization system should I choose for quarterly finance reports?"
    )
    classic = [
      {
        id: "f1",
        text: "The recommendation should name one candidate and the main tradeoff.",
        score: 0.9,
        kind: :fact,
        provenance: { sources: [{ type: "trace", id: "t1" }] }
      }
    ]
    evidence_set = Llmemory::ZeroMem::EvidenceSet.new(
      route: :hierarchy,
      profile: profile_choice,
      evidence: [
        evidence_row(
          trace_id: "t1",
          content: "Model Boreal preserved numerical claims in the quarterly finance report evaluation.",
          score: 0.7
        )
      ],
      metrics: {}
    )

    result = fusion.fuse(classic_candidates: classic, evidence_set: evidence_set, max_tokens: 500)
    expect(result.items.map { |item| item[:text] }.join(" ")).to include("Boreal")
  end

  it "keeps trace evidence for temporal queries" do
    classic = [
      {
        id: "f1",
        text: "Caroline visited LGBTQ support group on 7 May 2023",
        score: 0.7,
        temporal_score: 0.7,
        kind: :fact,
        event_date: "2023-05-07",
        provenance: { sources: [{ type: "trace", id: "t_gold" }] }
      }
    ]
    evidence_set = Llmemory::ZeroMem::EvidenceSet.new(
      route: :hierarchy,
      profile: profile,
      evidence: [
        evidence_row(trace_id: "t_gold", content: "Went to LGBTQ support group yesterday.", score: 0.85)
      ],
      metrics: {}
    )

    result = fusion.fuse(classic_candidates: classic, evidence_set: evidence_set, max_tokens: 800)
    kinds = result.items.map { |i| i[:kind] }
    expect(kinds).to include(:fact, :trace)
  end

  it "ranks an identity copula above an activity fact" do
    profile_id = Llmemory::ZeroMem::QueryProfiler.new.profile(
      "What is Caroline's identity?",
      language: :en
    )
    classic = [
      { id: "f1", text: "Caroline is going swimming with the kids", score: 0.95, temporal_score: 0.95, kind: :fact },
      { id: "f2", text: "Caroline is a transgender woman", score: 0.3, temporal_score: 0.3, kind: :fact }
    ]
    evidence_set = Llmemory::ZeroMem::EvidenceSet.new(
      route: :hierarchy, profile: profile_id, evidence: [], metrics: {}
    )
    result = fusion.fuse(classic_candidates: classic, evidence_set: evidence_set, max_tokens: 400)
    expect(result.items.first[:text]).to include("transgender")
  end

  it "ranks a rare query term above a generic higher-ranked trace" do
    deadline = Llmemory::ZeroMem::QueryProfiler.new.profile(
      "What is the deadline for the sustainability narrative pack?",
      language: :en
    )
    generic = Array.new(6) do |i|
      evidence_row(trace_id: "g#{i}", content: "The incomplete impact data phase is still open for review #{i}.", score: 0.9 - (i * 0.01))
    end
    rare = evidence_row(
      trace_id: "rare",
      content: "Reporting locks the sustainability narrative pack on July 17.",
      score: 0.2
    )
    evidence_set = Llmemory::ZeroMem::EvidenceSet.new(
      route: :hierarchy,
      profile: deadline,
      evidence: generic + [rare],
      metrics: {}
    )

    result = fusion.fuse(classic_candidates: [], evidence_set: evidence_set, max_tokens: 800)
    expect(result.items.first[:text]).to include("narrative pack")
  end

  it "keeps an undated seed when a current-state fact omits the named evidence" do
    profile_now = Llmemory::ZeroMem::QueryProfiler.new.profile(
      "What is the main tradeoff I should expect from the summarization system?"
    )
    evidence_set = Llmemory::ZeroMem::EvidenceSet.new(
      route: :hierarchy,
      profile: profile_now,
      evidence: [
        evidence_row(
          trace_id: "other",
          content: "Model Atlas is familiar and quick to set up for text summarization.",
          score: 0.95,
          occurred_at_inferred: true
        ),
        evidence_row(
          trace_id: "cue",
          content: "Model Boreal preserved numerical claims under compression in the quarterly finance reports.",
          score: 0.15,
          occurred_at_inferred: true
        )
      ],
      metrics: {}
    )

    result = fusion.fuse(classic_candidates: [], evidence_set: evidence_set, max_tokens: 400)
    expect(result.items.map { |item| item[:text] }.join(" ")).to include("Boreal")
  end

  it "keeps the newest seed when a current-state query only has room for two traces" do
    profile_now = Llmemory::ZeroMem::QueryProfiler.new.profile(
      "I ended up volunteering for that project, and now I'm totally overwhelmed."
    )
    older = [
      evidence_row(trace_id: "old1", content: "I love volunteering at the project every weekend.", score: 0.9),
      evidence_row(trace_id: "old2", content: "The project left me totally overwhelmed last spring.", score: 0.8)
    ]
    newest = evidence_row(
      trace_id: "cue",
      content: "After learning to say no, I feel less stressed.",
      score: 0.05,
      occurred_at: Time.utc(2023, 11, 5)
    )
    evidence_set = Llmemory::ZeroMem::EvidenceSet.new(
      route: :hierarchy,
      profile: profile_now,
      evidence: older + [newest],
      metrics: {}
    )

    result = fusion.fuse(classic_candidates: [], evidence_set: evidence_set, max_tokens: 400)
    expect(result.items.map { |item| item[:text] }.join(" ")).to include("less stressed")
  end

  it "excludes resource rows when skip_resources is true" do
    classic = [
      { id: "r1", text: "raw conversation dump", score: 0.5, kind: :resource }
    ]
    evidence_set = Llmemory::ZeroMem::EvidenceSet.new(
      route: :hierarchy,
      profile: profile,
      evidence: [],
      metrics: {}
    )
    result = fusion.fuse(classic_candidates: classic, evidence_set: evidence_set, max_tokens: 200)
    expect(result.items).to be_empty
  end
end
