# frozen_string_literal: true

require "spec_helper"
require "llmemory/mcp"

RSpec.describe Llmemory::MCP::Tools::MemoryConsolidate do
  before do
    Llmemory.reset_configuration!
    Llmemory.configuration.short_term_store = :memory
    Llmemory.configuration.long_term_store = :memory
    Llmemory.configuration.long_term_type = :file_based
  end

  describe ".call" do
    it "returns message when no messages to consolidate" do
      response = described_class.call(user_id: "user123")

      expect(response).to be_a(::MCP::Tool::Response)
      expect(response.content.first[:text]).to include("No messages to consolidate")
    end

    it "round-trips add_message and consolidate with shared memory stores" do
      Llmemory.configure { |c| c.shared_memory_stores = true }
      extractor = double(
        "FactExtractor",
        classify_item: "general",
        classify_items: {},
        evolve_summary: "summary",
        extract_items: []
      )
      allow(Llmemory::Extractors::FactExtractor).to receive(:new).and_return(extractor)

      Llmemory::MCP::Tools::MemoryAddMessage.call(
        user_id: "user123",
        role: "user",
        content: "I prefer tea"
      )

      response = described_class.call(user_id: "user123")
      expect(response.content.first[:text]).to include("Consolidated 1 messages")
    end

    it "handles errors gracefully" do
      allow(Llmemory::Memory).to receive(:new).and_raise(StandardError.new("Error"))

      response = described_class.call(user_id: "user123")

      expect(response.instance_variable_get(:@error)).to be true
    end
  end

  describe "tool definition" do
    it "requires only user_id" do
      schema = described_class.input_schema_value.to_h
      expect(schema[:required]).to eq(["user_id"])
    end

    it "has optional session_id and clear_session" do
      schema = described_class.input_schema_value.to_h
      expect(schema[:properties]).to have_key(:session_id)
      expect(schema[:properties]).to have_key(:clear_session)
    end
  end
end
