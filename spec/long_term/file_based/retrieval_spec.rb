# frozen_string_literal: true

RSpec.describe Llmemory::LongTerm::FileBased::Retrieval do
  let(:user_id) { "user_1" }
  let(:storage) { Llmemory::LongTerm::FileBased::Storage.new }
  let(:llm_double) do
    double("LLM").tap do |d|
      allow(d).to receive(:invoke).with(/Query:.*Available Categories/).and_return('["preferences"]')
      allow(d).to receive(:invoke).with(/Can you answer the query/).and_return("YES")
      allow(d).to receive(:invoke).with(/Generate a short search phrase/).and_return("user prefers Ruby")
    end
  end
  let(:retrieval) { described_class.new(user_id: user_id, storage: storage, llm: llm_double) }

  before do
    storage.save_item(user_id, category: "preferences", content: "User prefers Ruby", source_resource_id: "r1")
    storage.save_category(user_id, "preferences", "User prefers Ruby and has used it for 5 years.")
  end

  describe "#retrieve" do
    it "returns summaries when categories are sufficient" do
      result = retrieval.retrieve("What does the user prefer?")
      expect(result).to be_a(Hash)
      expect(result["preferences"]).to include("Ruby")
    end

    it "returns empty hash when no categories exist" do
      storage_empty = Llmemory::LongTerm::FileBased::Storage.new
      retrieval_empty = described_class.new(user_id: "other_user", storage: storage_empty, llm: llm_double)
      expect(retrieval_empty.retrieve("test")).to eq({})
    end

    it "searches items when summaries are not sufficient" do
      allow(llm_double).to receive(:invoke).with(/Can you answer the query/).and_return("NO")
      result = retrieval.retrieve("What language?")
      expect(result).to be_an(Array)
      expect(result).to include("User prefers Ruby")
    end

    it "searches resources when no items match" do
      allow(llm_double).to receive(:invoke).with(/Can you answer the query/).and_return("NO")
      allow(llm_double).to receive(:invoke).with(/Generate a short search phrase/).and_return("python")
      storage.save_resource(user_id, "User mentioned Python briefly")
      result = retrieval.retrieve("What language?")
      expect(result).to be_an(Array)
    end
  end
end
