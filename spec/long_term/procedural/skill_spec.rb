# frozen_string_literal: true

RSpec.describe Llmemory::LongTerm::Procedural::Skill do
  def build(**overrides)
    described_class.new(**{ id: "s1", user_id: "u1", name: "rollback", body: "kubectl rollout undo" }.merge(overrides))
  end

  describe "#success_rate" do
    it "is neutral (0.5) for unproven skills" do
      expect(build.success_rate).to eq(0.5)
    end

    it "is the ratio of successes to total outcomes" do
      expect(build(success_count: 3, failure_count: 1).success_rate).to eq(0.75)
    end
  end

  describe "kind normalization" do
    it "keeps a valid kind" do
      expect(build(kind: "code").kind).to eq("code")
    end

    it "falls back to the default kind for unknown values" do
      expect(build(kind: "weird").kind).to eq("prompt")
    end
  end

  describe "#searchable_text" do
    it "combines name, description and body" do
      text = build(description: "revert a bad deploy").searchable_text
      expect(text).to include("rollback", "revert a bad deploy", "kubectl rollout undo")
    end
  end

  describe "round-trip to_h/from_h" do
    it "preserves fields" do
      original = build(description: "d", kind: "code", version: 3, success_count: 2, failure_count: 1)
      restored = described_class.from_h(original.to_h)
      expect(restored.name).to eq("rollback")
      expect(restored.kind).to eq("code")
      expect(restored.version).to eq(3)
      expect(restored.success_count).to eq(2)
      expect(restored.failure_count).to eq(1)
    end
  end
end
