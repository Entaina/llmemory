# frozen_string_literal: true

RSpec.describe Llmemory::Tokenizer do
  describe ".tokenize" do
    it "downcases and splits on word boundaries, dropping <2-char tokens" do
      expect(described_class.tokenize("Revert a Bad Deploy!")).to eq(%w[revert bad deploy])
    end

    it "returns [] for blank text" do
      expect(described_class.tokenize("  ")).to eq([])
    end
  end

  describe ".matches?" do
    it "matches when any query token is a substring (multi-word queries work)" do
      expect(described_class.matches?("revert a bad deploy", "revert deploy")).to be true
    end

    it "preserves single partial-term matching" do
      expect(described_class.matches?("User prefers Ruby", "rub")).to be true
    end

    it "is an OR across tokens (one hit is enough)" do
      expect(described_class.matches?("kubectl rollout undo", "deploy rollout")).to be true
    end

    it "returns false when no token matches" do
      expect(described_class.matches?("ruby on rails", "kubernetes python")).to be false
    end

    it "matches everything for an empty/tokenless query" do
      expect(described_class.matches?("anything", "")).to be true
      expect(described_class.matches?("anything", "  ! ?")).to be true
    end
  end
end
