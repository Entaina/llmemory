# frozen_string_literal: true

RSpec.describe Llmemory::Extractors::FactExtractor do
  let(:llm) do
    Object.new.tap do |d|
      def d.invoke(prompt)
        if prompt.include?("Known facts")
          '[{"content":"Caroline moved from Sweden","importance":0.8,"category":"personal_life","subject":"Caroline","predicate":"home_country"}]'
        else
          "[]"
        end
      end
    end
  end

  subject(:extractor) { described_class.new(llm: llm) }

  it "includes known facts in the extraction prompt" do
    items = extractor.extract_items(
      "She said her home country was beautiful.",
      known_facts: ["Caroline moved from Sweden"]
    )
    expect(items).to be_an(Array)
  end
end
