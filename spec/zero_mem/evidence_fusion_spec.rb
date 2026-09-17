# frozen_string_literal: true

RSpec.describe Llmemory::ZeroMem::EvidenceFusion do
  let(:fusion) { described_class.new }

  describe "#min_max" do
    it "returns empty hash for empty input" do
      expect(fusion.min_max({})).to eq({})
    end

    it "normalizes a single score to 0.5 when max equals min" do
      expect(fusion.min_max({ "a" => 2.0 })).to eq({ "a" => 0.5 })
    end

    it "uses 0.5 for all ids when every score is equal" do
      expect(fusion.min_max({ "a" => 1.0, "b" => 1.0 })).to eq({ "a" => 0.5, "b" => 0.5 })
    end

    it "spreads two distinct scores across 0 and 1" do
      norm = fusion.min_max({ "a" => 0.0, "b" => 1.0 })
      expect(norm["a"]).to eq(0.0)
      expect(norm["b"]).to eq(1.0)
    end
  end

  describe "#fuse" do
    it "combines views with rho weights" do
      rows = fusion.fuse(
        graph_scores: { "t1" => 1.0, "t2" => 0.0 },
        hierarchy_scores: { "t1" => 0.0, "t2" => 1.0 },
        weights: { graph: 0.6, hierarchy: 0.4 }
      )
      by_id = rows.each_with_object({}) { |r, h| h[r[:trace_id]] = r }
      expect(by_id["t1"][:final]).to be > by_id["t2"][:final]
      expect(by_id["t1"][:sources]).to contain_exactly(:graph, :hierarchy)
    end
  end
end
