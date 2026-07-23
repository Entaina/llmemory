# frozen_string_literal: true

RSpec.describe Llmemory::Extractors::EntityRelationExtractor do
  let(:llm_double) do
    double("LLM").tap do |d|
      allow(d).to receive(:invoke).with(/Infer entities and relations/).and_return(<<~JSON)
        {"entities": [{"type": "person", "name": "User"}, {"type": "company", "name": "OpenAI"}],
         "relations": [{"subject": "User", "predicate": "works_at", "object": "OpenAI"}]}
      JSON
    end
  end
  let(:extractor) { described_class.new(llm: llm_double) }

  describe "#extract" do
    it "returns entities and relations from conversation text" do
      result = extractor.extract("I work at OpenAI.")
      expect(result).to be_a(Hash)
      expect(result[:entities]).to be_an(Array)
      expect(result[:relations]).to be_an(Array)
      expect(result[:entities].map { |e| e[:name] }).to include("User", "OpenAI")
      expect(result[:relations].first).to include(subject: "User", predicate: "works_at", object: "OpenAI")
    end

    it "normalizes predicate to snake_case" do
      allow(llm_double).to receive(:invoke).with(/Infer entities and relations/).and_return(
        '{"entities": [], "relations": [{"subject": "A", "predicate": "works at", "object": "B"}]}'
      )
      result = extractor.extract("A works at B.")
      expect(result[:relations].first[:predicate]).to eq("works_at")
    end

    it "returns empty arrays when LLM returns invalid JSON" do
      allow(llm_double).to receive(:invoke).and_return("not json at all")
      result = extractor.extract("Hello")
      expect(result[:entities]).to eq([])
      expect(result[:relations]).to eq([])
    end

    it "preserves head and tail of long conversations in the prompt" do
      tail_marker = "UNIQUE_TAIL_MARKER_xyz"
      long_text = "#{'a' * 2000}#{'b' * 2000}#{tail_marker}"
      captured = nil
      allow(llm_double).to receive(:invoke) { |prompt| captured = prompt; '{"entities": [], "relations": []}' }
      extractor.extract(long_text)
      expect(captured).to include("[...]")
      expect(captured).to include("aaa")
      expect(captured).to include(tail_marker)
    end
  end
end
