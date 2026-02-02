# frozen_string_literal: true

require "spec_helper"
require "llmemory/mcp"

RSpec.describe Llmemory::MCP::Tools::MemorySearch do
  before do
    Llmemory.reset_configuration!
    Llmemory.configuration.short_term_store = :memory
    Llmemory.configuration.long_term_store = :memory
    Llmemory.configuration.long_term_type = :file_based
  end

  describe ".call" do
    it "returns no memories when store is empty" do
      response = described_class.call(query: "test", user_id: "user123")

      expect(response).to be_a(::MCP::Tool::Response)
      expect(response.content.first[:text]).to include("No memories found")
    end

    it "handles errors gracefully" do
      allow(Llmemory::ShortTerm::Stores::MemoryStore).to receive(:new).and_raise(StandardError.new("Test error"))

      response = described_class.call(query: "test", user_id: "user123")

      expect(response.instance_variable_get(:@error)).to be true
      expect(response.content.first[:text]).to include("Error")
    end
  end

  describe "tool definition" do
    it "has a description" do
      expect(described_class.description_value).to include("Search")
    end

    it "has required parameters in input schema" do
      schema = described_class.input_schema_value.to_h
      expect(schema[:required]).to include("query")
      expect(schema[:required]).to include("user_id")
    end
  end
end
