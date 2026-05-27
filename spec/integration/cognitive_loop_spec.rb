# frozen_string_literal: true

# Integration specs for the CoALA cognitive loop. These exercise the *seams*
# between features (not the units, which are covered elsewhere): episodic ->
# reflection -> semantic+provenance, skill outcomes -> retrieval ranking,
# working memory -> reasoning, and forgetting -> audit.
RSpec.describe "Cognitive memory loop (CoALA)" do
  let(:user_id) { "agent_1" }

  describe "experience -> reflection -> traceable knowledge (P1 + P2 + P10)" do
    let(:llm) do
      double("LLM").tap do |d|
        allow(d).to receive(:invoke).and_return(
          '[{"content": "Rollbacks restore service after a failed deploy", "confidence": 0.8}]'
        )
      end
    end
    let(:episodic) { Llmemory::LongTerm::Episodic::Memory.new(user_id: user_id) }
    let(:semantic) do
      Llmemory::LongTerm::FileBased::Memory.new(
        user_id: user_id, storage: Llmemory::LongTerm::FileBased::Storages::MemoryStorage.new, llm: llm
      )
    end

    it "turns recorded episodes into a semantic insight traceable to its sources" do
      e1 = episodic.record_episode(steps: [{ action: "rolled back" }], outcome: "recovered")
      e2 = episodic.record_episode(steps: [{ action: "rolled back" }], outcome: "recovered")

      Llmemory::Reflection::Reflector.new(episodic: episodic, semantic: semantic, llm: llm).reflect(window: 10)

      insight = semantic.read("Rollbacks").first
      expect(insight[:text]).to include("Rollbacks restore service")

      provenance = semantic.storage.get_all_items(user_id).first[:provenance]
      expect(provenance[:method]).to eq("reflection")
      expect(provenance[:sources].map { |s| s[:id] }).to contain_exactly(e1, e2)
    end
  end

  describe "skill outcomes shape retrieval ranking (P6 + P3)" do
    let(:skills) { Llmemory::LongTerm::Procedural::Memory.new(user_id: user_id) }

    it "ranks a proven skill above an unproven one via importance" do
      proven = skills.register_skill(name: "rollback", body: "kubectl rollout undo")
      skills.register_skill(name: "rollback-helper", body: "rollback notes")
      2.times { skills.report_outcome(proven, success: true) }

      ranked = Llmemory::Retrieval::TemporalRanker.new.rank(skills.search_candidates("rollback"))
      expect(ranked.first[:id]).to eq(proven)
      expect(ranked.first[:importance]).to eq(1.0)
    end
  end

  describe "working memory drives reasoning (P4 + P7)" do
    let(:llm) { double("LLM").tap { |d| allow(d).to receive(:invoke).and_return("restart the worker") } }

    it "reads slots into the prompt and writes the result back" do
      wm = Llmemory::WorkingMemory.new(
        user_id: user_id, session_id: "s", store: Llmemory::ShortTerm::Stores::MemoryStore.new
      )
      wm.current_task = "fix the queue"

      prompts = []
      allow(llm).to receive(:invoke) { |p| prompts << p; "restart the worker" }

      Llmemory::Actions::Reason.call(
        working_memory: wm, template: "Task: {{current_task}}. Next?", into: :scratchpad, llm: llm
      )

      expect(prompts.first).to include("fix the queue")
      expect(wm.scratchpad).to eq("restart the worker")
    end
  end

  describe "forgetting is uniform and audited (P9 + P5)" do
    let(:episodic) { Llmemory::LongTerm::Episodic::Memory.new(user_id: user_id) }

    it "removes by the same id read exposes and records an audit entry" do
      id = episodic.record_episode(steps: [{ action: "obsolete step" }])
      retrieved_id = episodic.read("obsolete").first[:id]
      expect(retrieved_id).to eq(id)

      expect(episodic.forget(ids: [retrieved_id], reason: "cleanup")).to eq(1)
      expect(episodic.count).to eq(0)
      expect(episodic.forget_log.entries(user_id).last).to include(memory_type: "episodic", reason: "cleanup")
    end
  end
end
