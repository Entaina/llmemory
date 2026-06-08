# frozen_string_literal: true

RSpec.describe Llmemory::SkillMining::Miner do
  let(:user_id) { "user_1" }
  let(:episodic) { Llmemory::LongTerm::Episodic::Memory.new(user_id: user_id) }
  let(:procedural) { Llmemory::LongTerm::Procedural::Memory.new(user_id: user_id) }
  let(:llm) do
    double("LLM").tap do |d|
      allow(d).to receive(:invoke).and_return(
        '[{"name": "rollback_on_failure", "kind": "prompt", "body": "Roll back to the last good release.", "description": "Recover after a failed deploy", "confidence": 0.85}]'
      )
    end
  end
  let(:miner) { described_class.new(episodic: episodic, procedural: procedural, llm: llm) }

  describe "#mine" do
    let!(:e1) { episodic.record_episode(steps: [{ observation: "deploy failed", action: "rolled back" }], outcome: "success") }
    let!(:e2) { episodic.record_episode(steps: [{ observation: "deploy failed again", action: "rolled back" }], outcome: "success") }

    it "returns skill proposals without writing anything (human-in-the-loop)" do
      proposals = miner.mine(window: 10)
      expect(proposals.size).to eq(1)
      expect(proposals.first).to include(
        name: "rollback_on_failure", kind: "prompt", confidence: 0.85
      )
      expect(procedural.count).to eq(0)
    end

    it "registers proposals with provenance when auto_register is true" do
      ids = miner.mine(window: 10, auto_register: true)
      expect(ids.size).to eq(1)
      expect(procedural.count).to eq(1)

      skill = procedural.get_skill(ids.first)
      expect(skill.name).to eq("rollback_on_failure")
      prov = skill.provenance
      expect(prov[:method]).to eq("skill_mining")
      expect(prov[:confidence]).to eq(0.85)
      expect(prov[:sources].map { |s| s[:type] }.uniq).to eq(["episode"])
      expect(prov[:sources].map { |s| s[:id] }).to contain_exactly(e1, e2)
    end

    it "passes the episode content to the LLM" do
      miner.mine(window: 10)
      expect(llm).to have_received(:invoke).with(/rolled back/)
    end

    it "filters episodes by outcome allowlist (deterministic pre-filter)" do
      episodic.record_episode(steps: [{ action: "ignored" }], outcome: "failure")
      miner.mine(window: 10, outcomes: ["success"])
      expect(llm).to have_received(:invoke) do |prompt|
        expect(prompt).not_to include("ignored")
      end
    end

    it "normalizes an invalid kind to the default" do
      allow(llm).to receive(:invoke).and_return(
        '[{"name": "x", "kind": "bogus", "body": "do x", "confidence": 0.5}]'
      )
      expect(miner.mine(window: 10).first[:kind]).to eq("prompt")
    end

    it "skips proposals with blank name or body" do
      allow(llm).to receive(:invoke).and_return(
        '[{"name": "", "body": "b", "confidence": 0.9}, {"name": "good", "body": "do it", "confidence": 0.7}]'
      )
      proposals = miner.mine(window: 10)
      expect(proposals.map { |p| p[:name] }).to eq(["good"])
    end
  end

  it "returns [] when there are no episodes (no LLM call)" do
    expect(miner.mine).to eq([])
    expect(llm).not_to have_received(:invoke)
  end

  it "returns [] when the LLM yields no parseable proposals" do
    allow(llm).to receive(:invoke).and_return("Sorry, nothing reusable.")
    episodic.record_episode(steps: [{ action: "did something" }], outcome: "success")
    expect(miner.mine).to eq([])
    expect(procedural.count).to eq(0)
  end

  it "returns [] when the outcome filter excludes every episode" do
    episodic.record_episode(steps: [{ action: "act" }], outcome: "failure")
    expect(miner.mine(outcomes: ["success"])).to eq([])
    expect(llm).not_to have_received(:invoke)
  end
end
