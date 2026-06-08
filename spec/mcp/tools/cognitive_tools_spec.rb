# frozen_string_literal: true

require "spec_helper"
require "llmemory/mcp"

RSpec.describe "Cognitive MCP tools (SF10)" do
  before do
    Llmemory.reset_configuration!
    Llmemory.configuration.short_term_store = :memory
    Llmemory.configuration.long_term_store = :memory
    Llmemory.configuration.long_term_type = :file_based
  end

  describe Llmemory::MCP::Tools::MemoryEpisodeRecord do
    it "records an episode and returns its id" do
      response = described_class.call(
        user_id: "u1",
        steps: [{ observation: "deploy failed", action: "rolled back", result: "service restored" }],
        outcome: "recovered",
        importance: 0.8
      )
      expect(response.content.first[:text]).to match(/Episode recorded: ep_/)
    end
  end

  describe Llmemory::MCP::Tools::MemoryEpisodes do
    it "reports an empty list when there are no episodes" do
      response = described_class.call(user_id: "u1")
      expect(response.content.first[:text]).to include("No episodes for user u1")
    end
  end

  describe Llmemory::MCP::Tools::MemorySkillRegister do
    it "registers a skill and returns its id" do
      response = described_class.call(user_id: "u1", name: "rollback", body: "kubectl rollout undo")
      expect(response.content.first[:text]).to match(/Skill registered: skill_/)
    end
  end

  describe "skill outcome + listing share storage" do
    let(:storage) { Llmemory::LongTerm::Procedural::Storages::MemoryStorage.new }
    before { allow(Llmemory::LongTerm::Procedural::Storages).to receive(:build).and_return(storage) }

    it "registers, reports an outcome and lists the skill with success rate" do
      Llmemory::MCP::Tools::MemorySkillRegister.call(user_id: "u1", name: "rollback", body: "kubectl rollout undo")
      skill = Llmemory::LongTerm::Procedural::Memory.new(user_id: "u1").skills.first

      Llmemory::MCP::Tools::MemorySkillReport.call(user_id: "u1", skill_id: skill.id, success: true)
      response = Llmemory::MCP::Tools::MemorySkills.call(user_id: "u1")
      expect(response.content.first[:text]).to include("rollback").and include("1.00")
    end
  end

  describe Llmemory::MCP::Tools::MemorySkillReport do
    it "returns an error for an unknown skill id" do
      response = described_class.call(user_id: "u1", skill_id: "nope", success: true)
      expect(response.content.first[:text]).to include("Skill not found")
    end
  end

  describe Llmemory::MCP::Tools::MemoryForget do
    it "rejects an unknown memory_type" do
      response = described_class.call(user_id: "u1", memory_type: "weird", ids: ["x"])
      expect(response.content.first[:text]).to include("Unknown memory_type")
    end

    it "forgets episodic entries by id" do
      storage = Llmemory::LongTerm::Episodic::Storages::MemoryStorage.new
      allow(Llmemory::LongTerm::Episodic::Storages).to receive(:build).and_return(storage)
      ep_id = Llmemory::LongTerm::Episodic::Memory.new(user_id: "u1").record_episode(steps: [{ action: "x" }])

      response = described_class.call(user_id: "u1", memory_type: "episodic", ids: [ep_id], reason: "obsolete")
      expect(response.content.first[:text]).to include("Forgot 1 entries")
    end
  end

  # SF20 — cognitive maintenance surface
  describe Llmemory::MCP::Tools::MemoryMineSkills do
    it "reports nothing to mine on empty state (no LLM call)" do
      response = described_class.call(user_id: "u1")
      expect(response.content.first[:text]).to include("No skills could be mined for user u1")
    end

    it "returns proposals (without registering) when episodes are mined" do
      episodic = Llmemory::LongTerm::Episodic::Storages::MemoryStorage.new
      procedural = Llmemory::LongTerm::Procedural::Storages::MemoryStorage.new
      allow(Llmemory::LongTerm::Episodic::Storages).to receive(:build).and_return(episodic)
      allow(Llmemory::LongTerm::Procedural::Storages).to receive(:build).and_return(procedural)
      Llmemory::LongTerm::Episodic::Memory.new(user_id: "u1").record_episode(steps: [{ action: "rolled back" }], outcome: "success")
      allow_any_instance_of(Llmemory::SkillMining::Miner).to receive(:distill).and_return(
        [{ name: "rollback", kind: "prompt", body: "roll back", description: nil, confidence: 0.8 }]
      )

      response = described_class.call(user_id: "u1")
      expect(response.content.first[:text]).to include("1 skill proposal(s)").and include("rollback")
      expect(Llmemory::LongTerm::Procedural::Memory.new(user_id: "u1").count).to eq(0)
    end
  end

  describe Llmemory::MCP::Tools::MemoryMaintain do
    it "runs the pass and reports counts on empty state (no LLM call)" do
      response = described_class.call(user_id: "u1")
      text = response.content.first[:text]
      expect(text).to include("Cognitive pass for u1")
      expect(text).to include("insights: 0")
      expect(text).to include("skills mined: 0")
    end
  end
end
