# frozen_string_literal: true

RSpec.describe Llmemory::Provenance do
  describe ".build" do
    it "produces a JSON-safe hash with normalized fields" do
      prov = described_class.build(method: :fact_extraction, sources: [{ type: "resource", id: "r1" }], confidence: 0.9)
      expect(prov[:method]).to eq("fact_extraction")
      expect(prov[:sources]).to eq([{ type: "resource", id: "r1" }])
      expect(prov[:confidence]).to eq(0.9)
      expect(prov[:created_at]).to be_a(String)
      expect { Time.iso8601(prov[:created_at]) }.not_to raise_error
    end

    it "defaults confidence to nil and sources to empty" do
      prov = described_class.build(method: "m")
      expect(prov[:confidence]).to be_nil
      expect(prov[:sources]).to eq([])
    end

    it "normalizes bare source ids and drops sources without an id" do
      prov = described_class.build(method: "m", sources: ["abc", { id: "def" }, { type: "x" }, nil])
      expect(prov[:sources]).to eq([
        { type: "unknown", id: "abc" },
        { type: "unknown", id: "def" }
      ])
    end

    it "serializes a Time created_at to iso8601" do
      t = Time.utc(2026, 5, 27, 10, 0, 0)
      prov = described_class.build(method: "m", created_at: t)
      expect(prov[:created_at]).to eq(t.iso8601)
    end
  end

  describe ".from_resource" do
    it "links to the resource id" do
      prov = described_class.from_resource("res_1", method: "fact_extraction", confidence: 0.7)
      expect(prov[:sources]).to eq([{ type: "resource", id: "res_1" }])
      expect(prov[:method]).to eq("fact_extraction")
      expect(prov[:confidence]).to eq(0.7)
    end

    it "has no sources when resource id is nil" do
      prov = described_class.from_resource(nil, method: "fact_extraction")
      expect(prov[:sources]).to eq([])
    end
  end

  describe ".from_text_fingerprint" do
    it "records a stable 16-char fingerprint of the source text" do
      a = described_class.from_text_fingerprint("I work at Acme", method: "entity_relation_extraction")
      b = described_class.from_text_fingerprint("I work at Acme", method: "entity_relation_extraction")
      c = described_class.from_text_fingerprint("Something else", method: "entity_relation_extraction")

      expect(a[:sources].first[:type]).to eq("text_sha256")
      expect(a[:sources].first[:id]).to match(/\A[0-9a-f]{16}\z/)
      expect(a[:sources]).to eq(b[:sources])
      expect(a[:sources]).not_to eq(c[:sources])
    end

    it "has no sources for blank text" do
      prov = described_class.from_text_fingerprint("   ", method: "entity_relation_extraction")
      expect(prov[:sources]).to eq([])
    end
  end
end
