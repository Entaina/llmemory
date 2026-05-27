# frozen_string_literal: true

RSpec.describe Llmemory::LongTerm::Episodic::Episode do
  describe ".normalize_steps" do
    it "keeps the four step fields and drops non-hashes" do
      steps = described_class.normalize_steps([
        { observation: "saw X", action: "did Y", result: "got Z" },
        "garbage",
        { "action" => "string keys work" }
      ])
      expect(steps.size).to eq(2)
      expect(steps.first).to include(observation: "saw X", action: "did Y", result: "got Z")
      expect(steps.last[:action]).to eq("string keys work")
    end

    it "serializes step timestamps to iso8601" do
      t = Time.utc(2026, 5, 27, 10, 0, 0)
      steps = described_class.normalize_steps([{ action: "a", timestamp: t }])
      expect(steps.first[:timestamp]).to eq(t.iso8601)
    end
  end

  describe "#initialize" do
    it "defaults importance to 0.5" do
      ep = described_class.new(id: "e1", user_id: "u1")
      expect(ep.importance).to eq(0.5)
    end
  end

  describe "#searchable_text" do
    it "combines summary, outcome and step fields" do
      ep = described_class.new(
        id: "e1", user_id: "u1",
        summary: "Fixed a bug", outcome: "success",
        steps: [{ observation: "test failed", action: "patched code", result: "test passed" }]
      )
      text = ep.searchable_text
      expect(text).to include("Fixed a bug", "success", "test failed", "patched code", "test passed")
    end
  end

  describe "round-trip to_h/from_h" do
    it "preserves fields" do
      original = described_class.new(
        id: "e1", user_id: "u1",
        summary: "s", outcome: "success", importance: 0.9,
        steps: [{ observation: "o", action: "a", result: "r" }],
        created_at: Time.utc(2026, 5, 27, 10, 0, 0)
      )
      restored = described_class.from_h(original.to_h)
      expect(restored.id).to eq("e1")
      expect(restored.summary).to eq("s")
      expect(restored.outcome).to eq("success")
      expect(restored.importance).to eq(0.9)
      expect(restored.steps.first[:action]).to eq("a")
      expect(restored.created_at).to be_within(0.001).of(Time.utc(2026, 5, 27, 10, 0, 0))
    end
  end
end
