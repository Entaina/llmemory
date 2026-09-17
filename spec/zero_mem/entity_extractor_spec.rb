# frozen_string_literal: true

RSpec.describe Llmemory::ZeroMem::EntityExtractor do
  it "defines a non-generative contract" do
    extractor = Class.new(described_class) do
      def extract(text)
        [{ text: text, normalized: text.downcase, type: :entity, start: 0, end: 1 }]
      end
    end.new
    expect(extractor.generative?).to be(false)
    expect(extractor.extract("x").first[:normalized]).to eq("x")
  end
end
