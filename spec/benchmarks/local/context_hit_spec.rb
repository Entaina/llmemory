# frozen_string_literal: true

require File.expand_path("../../../benchmarks/local/scorers/context_hit", __dir__)

RSpec.describe LocalBenchmark::Scorers::ContextHit do
  describe ".hit?" do
    it "is true when gold answer appears in context" do
      query = { "gold_answer" => "Paris", "gold_trace_ids" => [] }
      expect(described_class.hit?(context: "User lives in Paris.", query: query)).to be(true)
    end

    it "is false when gold is absent from context" do
      query = { "gold_answer" => "Paris", "gold_trace_ids" => [] }
      expect(described_class.hit?(context: "User lives in London.", query: query)).to be(false)
    end

    it "matches Borges-style gold when context paraphrases attribution but keeps the quote" do
      gold = "According to Borges, 'The Library is a sphere whose exact center is any one of its hexagons and whose circumference is inaccessible.'"
      context = <<~CTX
        Borges notes, "The Library is a sphere whose exact center is any one of its hexagons and whose circumference is inaccessible." (Borges, 1941)
      CTX
      query = { "gold_answer" => gold, "gold_trace_ids" => [] }
      expect(described_class.hit?(context: context, query: query)).to be(true)
    end

    it "falls back to full gold trace text in context" do
      tid = "t1"
      turns = { tid => { "content" => "We adopted the kitten on March 3rd." } }
      query = { "gold_answer" => "March 4", "gold_trace_ids" => [tid] }
      ctx = "Earlier: We adopted the kitten on March 3rd."
      expect(described_class.hit?(context: ctx, query: query, turns: turns)).to be(true)
    end
  end

  describe ".applicable?" do
    it "is false for memsyco workloads" do
      expect(described_class.applicable?("workload_class" => "memsyco")).to be(false)
    end
  end
end
