# frozen_string_literal: true

RSpec.describe Llmemory::Retrieval::TemporalRanker do
  let(:ranker) { described_class.new(half_life_days: 30) }
  let(:old_time) { Time.now - (60 * 86400) }
  let(:new_time) { Time.now - (5 * 86400) }

  it "ranks by temporal score (newer favored with same relevance)" do
    candidates = [
      { text: "old", timestamp: old_time, score: 1.0 },
      { text: "new", timestamp: new_time, score: 1.0 }
    ]
    ranked = ranker.rank(candidates)
    expect(ranked.first[:text]).to eq("new")
    expect(ranked.first[:temporal_score]).to be > ranked.last[:temporal_score]
  end

  it "adds temporal_score to each candidate" do
    candidates = [{ text: "a", timestamp: Time.now, score: 0.8 }]
    ranked = ranker.rank(candidates)
    expect(ranked.first[:temporal_score]).to be_a(Numeric)
  end

  it "uses exponential decay (50% at half-life)" do
    half_life = 30
    ranker_exp = described_class.new(half_life_days: half_life)
    candidate_at_half_life = { text: "x", timestamp: Time.now - (half_life * 86400), score: 1.0 }
    ranked = ranker_exp.rank([candidate_at_half_life], now: Time.now)
    expect(ranked.first[:temporal_score]).to be_within(0.05).of(0.5)
  end

  it "uses exponential decay (25% at 2x half-life)" do
    half_life = 30
    ranker_exp = described_class.new(half_life_days: half_life)
    candidate_at_2x = { text: "x", timestamp: Time.now - (2 * half_life * 86400), score: 1.0 }
    ranked = ranker_exp.rank([candidate_at_2x], now: Time.now)
    expect(ranked.first[:temporal_score]).to be_within(0.05).of(0.25)
  end

  it "skips decay for evergreen candidates" do
    old_time = Time.now - (365 * 86400)
    candidates = [
      { text: "evergreen", timestamp: old_time, score: 1.0, evergreen: true },
      { text: "decayed", timestamp: old_time, score: 1.0 }
    ]
    ranked = ranker.rank(candidates)
    expect(ranked.first[:text]).to eq("evergreen")
    expect(ranked.first[:temporal_score]).to eq(1.0)
    expect(ranked.last[:temporal_score]).to be < 0.01
  end
end
