# frozen_string_literal: true

RSpec.describe Llmemory::WorkingMemory do
  let(:store) { Llmemory::ShortTerm::Stores::MemoryStore.new }
  let(:wm) { described_class.new(user_id: "u1", session_id: "s1", store: store) }

  describe "typed slots" do
    it "reads and writes each predefined slot" do
      wm.goals = ["plan trip"]
      wm.current_task = "book flights"
      wm.retrieved_context = "ctx"
      wm.scratchpad = "notes"
      wm.last_observation = "obs"
      wm.intermediate_reasoning = "thought"

      expect(wm.goals).to eq(["plan trip"])
      expect(wm.current_task).to eq("book flights")
      expect(wm.retrieved_context).to eq("ctx")
      expect(wm.scratchpad).to eq("notes")
      expect(wm.last_observation).to eq("obs")
      expect(wm.intermediate_reasoning).to eq("thought")
    end

    it "returns nil for unset slots" do
      expect(wm.goals).to be_nil
    end
  end

  describe "arbitrary slots" do
    it "supports set/get for custom keys" do
      wm.set(:budget, 1000)
      expect(wm.get(:budget)).to eq(1000)
    end

    it "lists only non-predefined slots in custom_slots" do
      wm.goals = ["g"]
      wm.set(:budget, 1000)
      expect(wm.custom_slots).to eq(budget: 1000)
    end

    it "updates several slots in one call" do
      wm.update(goals: ["a"], current_task: "t", priority: "high")
      expect(wm.goals).to eq(["a"])
      expect(wm.current_task).to eq("t")
      expect(wm.get(:priority)).to eq("high")
    end
  end

  describe "persistence" do
    it "survives a new instance backed by the same store" do
      wm.goals = ["persist me"]
      fresh = described_class.new(user_id: "u1", session_id: "s1", store: store)
      expect(fresh.goals).to eq(["persist me"])
    end
  end

  describe "isolation from checkpoint messages" do
    it "does not collide with a checkpoint sharing user_id/session_id and store" do
      wm.goals = ["intact"]
      checkpoint = Llmemory::ShortTerm::Checkpoint.new(user_id: "u1", session_id: "s1", store: store)
      checkpoint.save_state(messages: [{ role: :user, content: "hi" }])

      expect(wm.goals).to eq(["intact"])
      expect(checkpoint.restore_state[:messages].size).to eq(1)
    end
  end

  describe "#clear!" do
    it "removes all slots" do
      wm.goals = ["x"]
      wm.clear!
      expect(wm.to_h).to eq({})
    end
  end

  describe "Memory#working_memory" do
    it "exposes a lazily-built working memory parallel to the checkpoint" do
      memory = Llmemory::Memory.new(user_id: "u2", session_id: "s2")
      memory.working_memory.goals = ["from orchestrator"]
      expect(memory.working_memory.goals).to eq(["from orchestrator"])
      expect(memory.working_memory).to be_a(described_class)
    end
  end
end
