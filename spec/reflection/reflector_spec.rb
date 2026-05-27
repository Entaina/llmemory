# frozen_string_literal: true

RSpec.describe Llmemory::Reflection::Reflector do
  let(:user_id) { "user_1" }
  let(:episodic) { Llmemory::LongTerm::Episodic::Memory.new(user_id: user_id) }
  let(:semantic) do
    Llmemory::LongTerm::FileBased::Memory.new(
      user_id: user_id,
      storage: Llmemory::LongTerm::FileBased::Storages::MemoryStorage.new
    )
  end
  let(:llm) do
    double("LLM").tap do |d|
      allow(d).to receive(:invoke).and_return(
        '[{"content": "Rolling back on deploy failure restores service", "confidence": 0.85}]'
      )
    end
  end
  let(:reflector) { described_class.new(episodic: episodic, semantic: semantic, llm: llm) }

  describe "#reflect" do
    context "with recorded episodes" do
      let!(:e1) { episodic.record_episode(steps: [{ observation: "deploy failed", action: "rolled back" }], outcome: "recovered") }
      let!(:e2) { episodic.record_episode(steps: [{ observation: "deploy failed again", action: "rolled back" }], outcome: "recovered") }

      it "writes distilled insights into semantic memory" do
        ids = reflector.reflect(window: 10)
        expect(ids.size).to eq(1)
        contents = semantic.storage.get_all_items(user_id).map { |i| i[:content] }
        expect(contents).to include("Rolling back on deploy failure restores service")
      end

      it "stamps reflection provenance traceable to the source episodes" do
        reflector.reflect(window: 10)
        prov = semantic.storage.get_all_items(user_id).first[:provenance]
        expect(prov[:method]).to eq("reflection")
        expect(prov[:confidence]).to eq(0.85)
        expect(prov[:sources].map { |s| s[:type] }.uniq).to eq(["episode"])
        expect(prov[:sources].map { |s| s[:id] }).to contain_exactly(e1, e2)
      end

      it "writes the insight under the given category" do
        reflector.reflect(window: 10, category: "lessons")
        item = semantic.storage.get_all_items(user_id).first
        expect(item[:category]).to eq("lessons")
      end

      it "passes the LLM the episode content to reflect on" do
        reflector.reflect(window: 10)
        expect(llm).to have_received(:invoke).with(/rolled back/)
      end
    end

    it "returns [] when there are no episodes (no LLM call)" do
      expect(reflector.reflect).to eq([])
      expect(llm).not_to have_received(:invoke)
    end

    it "returns [] when the LLM yields no parseable insights" do
      allow(llm).to receive(:invoke).and_return("Sorry, no insights.")
      episodic.record_episode(steps: [{ action: "did something" }])
      expect(reflector.reflect).to eq([])
    end

    it "skips insights with blank content" do
      allow(llm).to receive(:invoke).and_return('[{"content": "", "confidence": 0.9}, {"content": "Valid insight", "confidence": 0.7}]')
      episodic.record_episode(steps: [{ action: "act" }])
      reflector.reflect
      contents = semantic.storage.get_all_items(user_id).map { |i| i[:content] }
      expect(contents).to eq(["Valid insight"])
    end
  end
end
