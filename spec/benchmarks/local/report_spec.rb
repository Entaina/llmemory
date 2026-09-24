# frozen_string_literal: true

require File.expand_path("../../../benchmarks/local/report", __dir__)

RSpec.describe LocalBenchmark::Report do
  describe ".retrieval_hit_aggregate" do
    it "counts false retrieval_hit values in the mean" do
      rows = [
        { retrieval_hit: true },
        { retrieval_hit: false },
        { retrieval_hit: false }
      ]
      agg = described_class.retrieval_hit_aggregate(rows)
      expect(agg[:count]).to eq(3)
      expect(agg[:mean]).to be_within(0.001).of(1.0 / 3.0)
    end

    it "ignores nil retrieval_hit" do
      rows = [{ retrieval_hit: true }, { retrieval_hit: nil }]
      agg = described_class.retrieval_hit_aggregate(rows)
      expect(agg[:count]).to eq(1)
      expect(agg[:mean]).to eq(1.0)
    end
  end
end
