# frozen_string_literal: true

RSpec.describe Llmemory::LongTerm::FileBased::Memory do
  let(:user_id) { "user_1" }
  let(:storage) { Llmemory::LongTerm::FileBased::Storage.new }
  let(:llm_double) do
    double("LLM").tap do |d|
      allow(d).to receive(:invoke).and_return("[]")
      allow(d).to receive(:invoke).with(/Extract discrete facts/).and_return('[{"content": "User prefers Ruby"}]')
      allow(d).to receive(:invoke).with(/Classify this fact/).and_return("preferences")
      allow(d).to receive(:invoke).with(/Memory Synchronization Specialist/).and_return("# User Profile\n- User prefers Ruby")
    end
  end
  let(:memory) { described_class.new(user_id: user_id, storage: storage, llm: llm_double) }

  describe "#memorize" do
    it "saves resource and items and updates category" do
      memory.memorize("I love Ruby and use it every day.")
      expect(storage.list_categories(user_id)).to include("preferences")
      expect(storage.load_category(user_id, "preferences")).to include("User prefers Ruby")
    end

    it "returns true" do
      expect(memory.memorize("Hello")).to be true
    end

    it "records provenance linking each item to its source resource" do
      memory.memorize("I love Ruby and use it every day.")
      item = storage.get_all_items(user_id).first
      prov = item[:provenance]
      expect(prov).not_to be_nil
      expect(prov[:method]).to eq("fact_extraction")
      expect(prov[:sources].first).to eq({ type: "resource", id: item[:source_resource_id] })
    end
  end

  describe "#remember_fact" do
    it "stores a fact with caller-supplied provenance, bypassing extraction" do
      prov = Llmemory::Provenance.build(method: "reflection", sources: [{ type: "episode", id: "ep_1" }], confidence: 0.8)
      id = memory.remember_fact(content: "Rollbacks restore service", category: "lessons", importance: 0.8, provenance: prov)
      expect(id).to start_with("item_")
      item = storage.get_all_items(user_id).find { |i| i[:id] == id }
      expect(item[:content]).to eq("Rollbacks restore service")
      expect(item[:category]).to eq("lessons")
      expect(item[:provenance][:method]).to eq("reflection")
    end

    it "returns nil for blank content" do
      expect(memory.remember_fact(content: "  ")).to be_nil
    end
  end

  describe "#forget" do
    it "removes items by id and audits the removal" do
      memory.memorize("I love Ruby and use it every day.")
      item = storage.get_all_items(user_id).first

      removed = memory.forget(ids: [item[:id]], reason: "user requested deletion")

      expect(removed).to eq(1)
      expect(storage.get_all_items(user_id).map { |i| i[:id] }).not_to include(item[:id])
      entry = memory.forget_log.entries(user_id).last
      expect(entry[:memory_type]).to eq("file_based")
      expect(entry[:ids]).to eq([item[:id]])
    end
  end

  describe "#retrieve" do
    before { memory.memorize("I prefer Ruby") }

    it "returns assembled context from search candidates" do
      result = memory.retrieve("What does the user prefer?")
      expect(result).to be_a(String)
      expect(result).to include("RELEVANT MEMORIES")
      expect(result).to include("Ruby")
    end
  end

  describe "#search_candidates" do
    before { memory.memorize("User prefers Python") }

    it "returns items and resources matching query" do
      candidates = memory.search_candidates("Python", top_k: 10)
      expect(candidates).to be_an(Array)
      expect(candidates.any? { |c| c[:text].to_s.include?("Python") }).to be true
    end

    it "respects user_id override" do
      candidates = memory.search_candidates("Python", user_id: "other_user", top_k: 10)
      expect(candidates).to eq([])
    end

    it "returns category summaries with evergreen flag" do
      memory.memorize("User prefers Python")
      candidates = memory.search_candidates("prefers", top_k: 10)
      evergreen_candidates = candidates.select { |c| c[:evergreen] }
      expect(evergreen_candidates).not_to be_empty
    end
  end

  describe "#memorize with noise_filter" do
    it "filters noise when noise_filter_enabled" do
      allow(Llmemory.configuration).to receive(:noise_filter_enabled).and_return(true)
      allow(Llmemory.configuration).to receive(:noise_filter_min_chars).and_return(10)
      allow(Llmemory.configuration).to receive(:daily_logs_enabled).and_return(false)

      llm_captured = []
      llm_spy = double("LLM").tap do |d|
        allow(d).to receive(:invoke).with(/Extract discrete facts/) do |arg|
          llm_captured << arg
          '[{"content": "User said hello"}]'
        end
        allow(d).to receive(:invoke).with(/Classify this fact/).and_return("general")
        allow(d).to receive(:invoke).with(/Memory Synchronization Specialist/).and_return("# Profile\n- User said hello")
      end

      mem = described_class.new(user_id: user_id, storage: storage, llm: llm_spy)
      mem.memorize("SHORT\nuser: Hello world this is long enough")

      expect(llm_captured.size).to eq(1)
      expect(llm_captured.first).not_to include("SHORT")
      expect(llm_captured.first).to include("Hello world")
    end
  end
end
