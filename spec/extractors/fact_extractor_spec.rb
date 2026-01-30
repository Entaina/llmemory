# frozen_string_literal: true

RSpec.describe Llmemory::Extractors::FactExtractor do
  let(:llm_double) do
    double("LLM").tap do |d|
      allow(d).to receive(:invoke).with(/Extract discrete facts/).and_return('[{"content": "User is vegan"}, {"content": "User prefers Python"}]')
      allow(d).to receive(:invoke).with(/Memory Synchronization Specialist/).and_return("# Profile\n- User is vegan")
      allow(d).to receive(:invoke).with(/Classify this fact/).and_return("preferences")
    end
  end
  let(:extractor) { described_class.new(llm: llm_double) }

  describe "#extract_items" do
    it "returns array of items with content" do
      items = extractor.extract_items("I am vegan and I prefer Python.")
      expect(items).to be_an(Array)
      expect(items.map { |i| i["content"] }).to include("User is vegan", "User prefers Python")
    end
  end

  describe "#evolve_summary" do
    it "returns updated summary from LLM" do
      result = extractor.evolve_summary(existing: "", new_memories: ["User is vegan"])
      expect(result).to include("vegan")
    end
  end

  describe "#classify_item" do
    it "returns category from LLM" do
      expect(extractor.classify_item("User prefers Python")).to eq("preferences")
    end

    it "returns general for empty content" do
      expect(extractor.classify_item("")).to eq("general")
    end
  end
end
