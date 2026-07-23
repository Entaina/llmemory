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

  describe "importance weighting" do
    let(:linear) { described_class.new(half_life_days: 30, importance_weight: 1.0) }

    it "favors higher importance when relevance and recency match" do
      candidates = [
        { text: "low", timestamp: new_time, score: 1.0, importance: 0.2 },
        { text: "high", timestamp: new_time, score: 1.0, importance: 0.9 }
      ]
      ranked = linear.rank(candidates)
      expect(ranked.first[:text]).to eq("high")
    end

    it "applies importance linearly at weight 1.0" do
      candidates = [{ text: "a", timestamp: Time.now, score: 1.0, importance: 0.5 }]
      ranked = linear.rank(candidates, now: Time.now)
      expect(ranked.first[:temporal_score]).to be_within(0.001).of(0.5)
    end

    it "ignores importance when weight is 0 (backward compatible)" do
      ranker0 = described_class.new(half_life_days: 30, importance_weight: 0.0)
      candidates = [
        { text: "low", timestamp: Time.now, score: 1.0, importance: 0.1 },
        { text: "high", timestamp: Time.now, score: 1.0, importance: 0.9 }
      ]
      ranked = ranker0.rank(candidates, now: Time.now)
      expect(ranked.map { |c| c[:temporal_score] }).to all(be_within(0.001).of(1.0))
    end

    it "treats missing importance as neutral (no penalty)" do
      candidates = [{ text: "a", timestamp: Time.now, score: 0.8 }]
      ranked = linear.rank(candidates, now: Time.now)
      expect(ranked.first[:temporal_score]).to be_within(0.001).of(0.8)
      expect(ranked.first[:importance]).to eq(1.0)
    end

    it "clamps importance into [0, 1]" do
      candidates = [
        { text: "over", timestamp: Time.now, score: 1.0, importance: 5.0 },
        { text: "under", timestamp: Time.now, score: 1.0, importance: -2.0 }
      ]
      ranked = linear.rank(candidates, now: Time.now)
      expect(ranked.find { |c| c[:text] == "over" }[:importance]).to eq(1.0)
      expect(ranked.find { |c| c[:text] == "under" }[:importance]).to eq(0.0)
    end

    it "softens importance influence at fractional weight" do
      ranker_half = described_class.new(half_life_days: 30, importance_weight: 0.5)
      candidates = [{ text: "a", timestamp: Time.now, score: 1.0, importance: 0.25 }]
      ranked = ranker_half.rank(candidates, now: Time.now)
      expect(ranked.first[:temporal_score]).to be_within(0.001).of(0.5)
    end
  end

  it "falls back to a safe half-life when configured to zero" do
    ranker = described_class.new(half_life_days: 0)
    ranked = ranker.rank([{ text: "a", timestamp: Time.now, score: 1.0 }], now: Time.now)
    expect(ranked.first[:temporal_score]).to be_finite
  end

  it "does not inflate scores for future timestamps" do
    ranker = described_class.new(half_life_days: 30)
    future = Time.now + 86_400
    ranked = ranker.rank([{ text: "a", timestamp: future, score: 1.0 }], now: Time.now)
    expect(ranked.first[:temporal_score]).to be <= 1.0
  end
end
