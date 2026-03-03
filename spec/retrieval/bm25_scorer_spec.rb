# frozen_string_literal: true

RSpec.describe Llmemory::Retrieval::Bm25Scorer do
  let(:scorer) { described_class.new }

  describe "#score_candidates" do
    it "returns empty when candidates empty" do
      expect(scorer.score_candidates("query", [])).to eq([])
    end

    it "assigns higher bm25 to documents matching query terms" do
      candidates = [
        { text: "python programming language", timestamp: Time.now, score: 1.0 },
        { text: "unrelated content about weather", timestamp: Time.now, score: 1.0 }
      ]
      scored = scorer.score_candidates("python programming", candidates)

      python_doc = scored.find { |c| c[:text].include?("python") }
      unrelated_doc = scored.find { |c| c[:text].include?("weather") }
      expect(python_doc[:bm25_score]).to be > unrelated_doc[:bm25_score]
    end

    it "returns normalized_bm25 between 0 and 1" do
      candidates = [
        { text: "hello world", timestamp: Time.now, score: 1.0 },
        { text: "goodbye world", timestamp: Time.now, score: 1.0 }
      ]
      scored = scorer.score_candidates("hello", candidates)
      scored.each do |c|
        expect(c[:normalized_bm25]).to be_between(0, 1)
      end
    end
  end
end
