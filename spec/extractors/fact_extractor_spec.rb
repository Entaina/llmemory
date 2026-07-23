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

    it "parses and returns importance score from LLM response" do
      llm_with_importance = double("LLM").tap do |d|
        allow(d).to receive(:invoke).with(/Extract discrete facts/).and_return(
          '[{"content": "User prefers dark mode", "importance": 0.9}, {"content": "User mentioned the weather", "importance": 0.4}]'
        )
      end
      extractor_imp = described_class.new(llm: llm_with_importance)
      items = extractor_imp.extract_items("User prefers dark mode. User mentioned the weather.")
      expect(items.size).to eq(2)
      expect(items.map { |i| i["importance"] }).to eq([0.9, 0.4])
    end

    it "defaults importance to 0.7 when missing from LLM response" do
      llm_no_importance = double("LLM").tap do |d|
        allow(d).to receive(:invoke).with(/Extract discrete facts/).and_return('[{"content": "User likes coffee"}]')
      end
      extractor_def = described_class.new(llm: llm_no_importance)
      items = extractor_def.extract_items("User likes coffee.")
      expect(items.size).to eq(1)
      expect(items.first["importance"]).to eq(0.7)
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

  describe "#classify_items" do
    it "classifies multiple facts in one structured-output call" do
      llm_batch = double("LLM").tap do |d|
        allow(d).to receive(:respond_to?).with(:invoke_with_json_schema).and_return(true)
        allow(d).to receive(:invoke_with_json_schema).and_return(
          "items" => [
            { "content" => "User is vegan", "category" => "preferences" },
            { "content" => "Works at Acme", "category" => "work_life" }
          ]
        )
      end
      batch_extractor = described_class.new(llm: llm_batch)
      result = batch_extractor.classify_items(["User is vegan", "Works at Acme"])
      expect(result).to eq(
        "User is vegan" => "preferences",
        "Works at Acme" => "work_life"
      )
      expect(llm_batch).to have_received(:invoke_with_json_schema).once
    end
  end
end
