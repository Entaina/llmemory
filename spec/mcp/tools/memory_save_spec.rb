# frozen_string_literal: true

require "spec_helper"
require "llmemory/mcp"

RSpec.describe Llmemory::MCP::Tools::MemorySave do
  before do
    Llmemory.reset_configuration!
    Llmemory.configuration.short_term_store = :memory
    Llmemory.configuration.long_term_store = :memory
    Llmemory.configuration.long_term_type = :file_based
  end

  describe ".call" do
    it "saves a memory with default category" do
      response = described_class.call(user_id: "user123", content: "User prefers dark mode")

      expect(response).to be_a(::MCP::Tool::Response)
      expect(response.content.first[:text]).to include("Memory saved successfully")
      expect(response.content.first[:text]).to include("observations")
      expect(response.content.first[:text]).to include("dark mode")
    end

    it "saves a memory with custom category" do
      response = described_class.call(
        user_id: "user123",
        content: "User likes Python",
        category: "preferences"
      )

      expect(response.content.first[:text]).to include("preferences")
    end

    it "handles errors gracefully" do
      allow(Llmemory::LongTerm::FileBased::Storages).to receive(:build).and_raise(StandardError.new("Storage error"))

      response = described_class.call(user_id: "user123", content: "test")

      expect(response.instance_variable_get(:@error)).to be true
      expect(response.content.first[:text]).to include("Error")
    end
  end

  describe "tool definition" do
    it "has required parameters" do
      schema = described_class.input_schema_value.to_h
      expect(schema[:required]).to include("user_id")
      expect(schema[:required]).to include("content")
    end

    it "has optional category" do
      schema = described_class.input_schema_value.to_h
      expect(schema[:required]).not_to include("category")
      expect(schema[:properties]).to have_key(:category)
    end
  end
end
