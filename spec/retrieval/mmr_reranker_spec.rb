# frozen_string_literal: true

RSpec.describe Llmemory::Retrieval::MmrReranker do
  let(:reranker) { described_class.new(lambda: 0.7) }

  describe "#rerank" do
    it "returns candidates unchanged when size <= 1" do
      expect(reranker.rerank([])).to eq([])
      expect(reranker.rerank([{ text: "a", temporal_score: 1.0 }])).to eq([{ text: "a", temporal_score: 1.0 }])
    end

    it "prefers diverse results over similar ones" do
      candidates = [
        { text: "python programming", temporal_score: 0.9 },
        { text: "python programming language", temporal_score: 0.85 },
        { text: "ruby programming", temporal_score: 0.8 }
      ]
      result = reranker.rerank(candidates)
      expect(result.size).to eq(3)
      expect(result.first[:text]).to eq("python programming")
      expect(result[1][:text]).to eq("ruby programming")
      expect(result[2][:text]).to eq("python programming language")
    end
  end
end
