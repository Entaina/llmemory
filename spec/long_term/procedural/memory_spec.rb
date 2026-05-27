# frozen_string_literal: true

RSpec.describe Llmemory::LongTerm::Procedural::Memory do
  let(:user_id) { "user_1" }
  let(:memory) { described_class.new(user_id: user_id) }

  describe "#register_skill" do
    it "returns a skill id" do
      id = memory.register_skill(name: "rollback", body: "kubectl rollout undo")
      expect(id).to start_with("skill_")
    end

    it "auto-increments version when a skill with the same name exists" do
      memory.register_skill(name: "rollback", body: "v1")
      memory.register_skill(name: "rollback", body: "v2")
      versions = memory.skills.map(&:version).sort
      expect(versions).to eq([1, 2])
    end

    it "respects an explicit version" do
      memory.register_skill(name: "rollback", body: "x", version: 7)
      expect(memory.skills.first.version).to eq(7)
    end
  end

  describe "#find_skill" do
    it "finds a skill by keyword across name, description and body" do
      memory.register_skill(name: "rollback", description: "revert a bad deploy", body: "kubectl rollout undo")
      expect(memory.find_skill("revert").name).to eq("rollback")
    end
  end

  describe "#report_outcome" do
    it "increments success and failure counts" do
      id = memory.register_skill(name: "rollback", body: "x")
      memory.report_outcome(id, success: true)
      memory.report_outcome(id, success: true)
      skill = memory.report_outcome(id, success: false)
      expect(skill.success_count).to eq(2)
      expect(skill.failure_count).to eq(1)
      expect(skill.success_rate).to be_within(0.001).of(0.666)
    end

    it "returns nil for an unknown skill" do
      expect(memory.report_outcome("nope", success: true)).to be_nil
    end
  end

  describe "#search_candidates" do
    it "surfaces proven utility as importance" do
      id = memory.register_skill(name: "rollback", body: "kubectl rollout undo")
      memory.register_skill(name: "rollback helper", body: "rollback notes")
      memory.report_outcome(id, success: true)

      candidates = memory.search_candidates("rollback")
      proven = candidates.max_by { |c| c[:importance] }
      expect(proven[:importance]).to eq(1.0)
      expect(candidates.map { |c| c[:importance] }).to include(0.5)
      expect(proven).to include(:text, :timestamp, :score, :importance)
    end

    it "isolates by user_id" do
      memory.register_skill(name: "rollback", body: "x")
      expect(memory.search_candidates("rollback", user_id: "other")).to eq([])
    end
  end

  describe "#count" do
    it "counts registered skills" do
      2.times { |i| memory.register_skill(name: "s#{i}", body: "b#{i}") }
      expect(memory.count).to eq(2)
    end
  end

  describe "#forget" do
    it "removes skills by id and audits the removal" do
      keep = memory.register_skill(name: "keep", body: "k")
      drop = memory.register_skill(name: "drop", body: "d")

      removed = memory.forget(ids: [drop], reason: "deprecated")

      expect(removed).to eq(1)
      expect(memory.skills.map(&:id)).to eq([keep])
      expect(memory.forget_log.entries(user_id).last[:memory_type]).to eq("procedural")
    end
  end
end
