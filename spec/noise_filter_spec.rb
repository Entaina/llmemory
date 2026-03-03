# frozen_string_literal: true

RSpec.describe Llmemory::NoiseFilter do
  let(:filter) { described_class.new(min_chars: 10, enabled: true) }

  describe "#filter" do
    it "removes lines shorter than min_chars" do
      input = "user: Hi\nassistant: Hello there"
      expect(filter.filter(input)).to eq("assistant: Hello there")
    end

    it "removes lines containing NO_REPLY" do
      input = "user: Test\nsystem: NO_REPLY marker"
      expect(filter.filter(input)).not_to include("NO_REPLY")
    end

    it "removes duplicate lines keeping first occurrence" do
      input = "user: Important content here\nuser: Important content here"
      expect(filter.filter(input)).to eq("user: Important content here")
    end

    it "returns original when disabled" do
      filter_disabled = described_class.new(enabled: false)
      input = "x"
      expect(filter_disabled.filter(input)).to eq("x")
    end

    it "filters lines shorter than min_chars with default config" do
      filter_default = described_class.new
      input = "Hi\nuser: Hello world here"
      expect(filter_default.filter(input)).to eq("user: Hello world here")
    end
  end

  describe ".filter?" do
    it "uses configuration when enabled" do
      allow(Llmemory.configuration).to receive(:noise_filter_enabled).and_return(true)
      allow(Llmemory.configuration).to receive(:noise_filter_min_chars).and_return(10)
      input = "x\nuser: This is long enough content"
      expect(described_class.filter?(input)).not_to include("\nx\n")
      expect(described_class.filter?(input)).to include("This is long enough")
    end

    it "returns original when configuration disabled" do
      allow(Llmemory.configuration).to receive(:noise_filter_enabled).and_return(false)
      input = "raw text"
      expect(described_class.filter?(input)).to eq("raw text")
    end
  end
end
