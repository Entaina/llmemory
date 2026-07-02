# frozen_string_literal: true

RSpec.describe Llmemory::LLM::Usage do
  describe ".zero" do
    it "returns zero usage" do
      usage = described_class.zero
      expect(usage.input_tokens).to eq(0)
      expect(usage.output_tokens).to eq(0)
      expect(usage.total_tokens).to eq(0)
    end
  end

  describe "#+" do
    it "sums token counts" do
      a = described_class.new(input_tokens: 10, output_tokens: 5, total_tokens: 15)
      b = described_class.new(input_tokens: 3, output_tokens: 2, total_tokens: 5)
      sum = a + b
      expect(sum.input_tokens).to eq(13)
      expect(sum.output_tokens).to eq(7)
      expect(sum.total_tokens).to eq(20)
    end
  end

  describe "#to_h" do
    it "returns a hash representation" do
      usage = described_class.new(input_tokens: 1, output_tokens: 2, total_tokens: 3)
      expect(usage.to_h).to eq(input_tokens: 1, output_tokens: 2, total_tokens: 3)
    end
  end
end
