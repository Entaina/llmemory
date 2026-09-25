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

  describe ".enrich with eval context" do
    it "exposes only context_hit, localization, and extraction_yield in bench_scores" do
      report = {
        rows: [{ context_hit: true, extraction_yield: { consolidate_sessions: 1, items_added: 2, empty_extractions: 0, parse_failures: 0 } }],
        means: { localization: { "recall@5" => 0.8 } }
      }
      enriched = described_class.enrich(report, bench: "locomo", eval: "context")
      expect(enriched[:eval]).to eq("context")
      expect(enriched[:bench_scores].keys).to contain_exactly(:context_hit, :localization, :extraction_yield)
      expect(enriched[:bench_scores][:context_hit][:mean]).to eq(1.0)
      expect(enriched[:bench_scores][:localization]["recall@5"]).to eq(0.8)
      expect(enriched[:bench_scores]).not_to have_key(:locomo_f1)
    end
  end
end
