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
end
