# frozen_string_literal: true

require File.expand_path("../../benchmarks/zero_mem/metrics", __dir__)
require File.expand_path("../../benchmarks/zero_mem/harness", __dir__)

RSpec.describe "ZM0 baseline harness" do
  describe ZeroMem::FixtureLoader do
    it "loads the ES/EN workload matrix" do
      conversations = described_class.validate_coverage!
      expect(conversations.size).to be >= 16
    end

    it "computes stable content hashes" do
      hashes = described_class.fixture_content_hashes
      expect(hashes.keys).to all(start_with("conversations/"))
      expect(hashes.values).to all(match(/\A[0-9a-f]{64}\z/))
    end

    it "merges standalone query files" do
      queries = described_class.all_queries
      expect(queries.map { |q| q["id"] }).to include("retrieval_es_single_hop_q1", "answer_en_single_hop_q1")
    end
  end

  describe ZeroMemBenchmark::Metrics do
    it "scores a synthetic ranking" do
      ranked = %w[t3 t1 t9]
      gold = %w[t1 t2]
      expect(described_class.recall_at_k(ranked, gold, 1)).to eq(0.0)
      expect(described_class.recall_at_k(ranked, gold, 3)).to eq(0.5)
      expect(described_class.mrr(ranked, gold)).to eq(0.5)
      expect(described_class.ndcg_at_k(ranked, gold, 3)).to be > 0.0
    end

    it "computes answer overlap metrics" do
      expect(described_class.token_f1("teal color", "teal")).to be > 0.5
      expect(described_class.bleu1("teal is nice", "teal")).to be_within(0.001).of(1.0 / 3)
      expect(described_class.rouge_l("the teal cat", "teal")).to be > 0.0
    end
  end

  describe ZeroMemBenchmark::Harness do
    it "runs :classic over fixtures without HTTP" do
      report = described_class.new(variant: :classic).run!
      expect(report[:queries]).to be >= 16
      expect(report[:means][:localization][:"recall@5"]).to be_a(Numeric)
      expect(report[:rows].first[:cost][:latency_ms]).to be_a(Numeric)
    end

    it "runs :zero_mem_full with zero invoke calls per query" do
      report = described_class.new(variant: :zero_mem_full).run!
      expect(report[:queries]).to be >= 16
      expect(report[:rows]).to all(satisfy { |row| row[:cost][:invoke_calls_delta].to_i.zero? })
    end
  end
end
