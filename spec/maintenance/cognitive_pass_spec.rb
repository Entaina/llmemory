# frozen_string_literal: true

RSpec.describe Llmemory::Maintenance::CognitivePass do
  let(:user_id) { "agent_1" }
  let(:episodic) { Llmemory::LongTerm::Episodic::Memory.new(user_id: user_id) }
  let(:procedural) { Llmemory::LongTerm::Procedural::Memory.new(user_id: user_id) }
  let(:semantic) do
    Llmemory::LongTerm::FileBased::Memory.new(
      user_id: user_id, storage: Llmemory::LongTerm::FileBased::Storages::MemoryStorage.new, llm: llm
    )
  end
  # Reflection and mining share the LLM but send different prompts; respond in
  # the shape each step expects.
  let(:insight_json) { '[{"content": "Rollbacks restore service", "confidence": 0.8}]' }
  let(:skill_json) do
    '[{"name": "rollback_on_failure", "kind": "prompt", "body": "Roll back on failure.", "confidence": 0.85}]'
  end
  let(:llm) do
    double("LLM").tap do |d|
      allow(d).to receive(:invoke) do |prompt|
        prompt.include?("reusable skill") ? skill_json : insight_json
      end
    end
  end

  before do
    episodic.record_episode(steps: [{ action: "rolled back" }], outcome: "success")
    episodic.record_episode(steps: [{ action: "rolled back" }], outcome: "success")
  end

  describe ".run!" do
    it "aggregates reflect, mine and expire into one report" do
      report = described_class.run!(
        user_id, episodic: episodic, procedural: procedural, semantic: semantic,
        llm: llm, mine_skills: true
      )

      expect(report[:insights].size).to eq(1)
      expect(report[:mined].size).to eq(1)
      expect(report[:expired]).to eq(episodic: 0, procedural: 0)
      expect(report[:errors]).to be_empty
      expect(report[:consolidated]).to be_nil # no memory: supplied
    end

    it "reflects but does not mine skills when mine_skills is false" do
      report = described_class.run!(
        user_id, episodic: episodic, procedural: procedural, semantic: semantic,
        llm: llm, mine_skills: false
      )
      expect(report[:insights].size).to eq(1)
      expect(report[:mined]).to eq([])
      expect(procedural.count).to eq(0)
    end

    it "defaults mine_skills to config.skill_mining_enabled" do
      allow(Llmemory.configuration).to receive(:skill_mining_enabled).and_return(true)
      report = described_class.run!(
        user_id, episodic: episodic, procedural: procedural, semantic: semantic, llm: llm
      )
      expect(report[:mined].size).to eq(1)
    end

    it "isolates a failing step without aborting the others" do
      allow(semantic).to receive(:remember_fact).and_raise(StandardError, "boom")

      report = described_class.run!(
        user_id, episodic: episodic, procedural: procedural, semantic: semantic,
        llm: llm, mine_skills: true
      )

      expect(report[:errors]).to have_key(:reflect)
      expect(report[:errors][:reflect]).to eq("boom")
      expect(report[:mined].size).to eq(1) # mining still ran
      expect(report[:expired]).to eq(episodic: 0, procedural: 0)
    end

    it "runs consolidate! when a memory is supplied" do
      memory = instance_double(Llmemory::Memory)
      allow(memory).to receive(:consolidate!).and_return(true)

      report = described_class.run!(
        user_id, memory: memory, episodic: episodic, procedural: procedural,
        semantic: semantic, llm: llm, reflect: false, mine_skills: false, expire: false
      )

      expect(memory).to have_received(:consolidate!)
      expect(report[:consolidated]).to be(true)
    end
  end
end
