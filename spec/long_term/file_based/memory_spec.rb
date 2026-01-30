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
  end

  describe "#retrieve" do
    before do
      allow(llm_double).to receive(:invoke).with(/Query:.*Available Categories/).and_return('["preferences"]')
      allow(llm_double).to receive(:invoke).with(/Can you answer the query/).and_return("YES")
      memory.memorize("I prefer Ruby")
    end

    it "returns summaries for relevant categories" do
      result = memory.retrieve("What does the user prefer?")
      expect(result).to be_a(Hash)
      expect(result["preferences"]).not_to be_nil
      expect(result["preferences"].to_s).not_to be_empty
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
  end
end
