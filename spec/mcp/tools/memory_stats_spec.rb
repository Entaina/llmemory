# frozen_string_literal: true

require "spec_helper"
require "llmemory/mcp"

RSpec.describe Llmemory::MCP::Tools::MemoryStats do
  before do
    Llmemory.reset_configuration!
    Llmemory.configuration.short_term_store = :memory
    Llmemory.configuration.long_term_store = :memory
    Llmemory.configuration.long_term_type = :file_based
  end

  describe ".call" do
    it "returns stats for empty user" do
      response = described_class.call(user_id: "user123")

      expect(response).to be_a(::MCP::Tool::Response)
      text = response.content.first[:text]
      expect(text).to include("Memory Statistics for user 'user123'")
      expect(text).to include("SHORT-TERM MEMORY")
      expect(text).to include("LONG-TERM MEMORY")
      expect(text).to include("Sessions: 0")
      expect(text).to include("Total messages: 0")
    end

    it "handles errors gracefully" do
      allow(Llmemory::ShortTerm::Stores::MemoryStore).to receive(:new).and_raise(StandardError.new("Error"))

      response = described_class.call(user_id: "user123")

      expect(response.instance_variable_get(:@error)).to be true
    end
  end

  describe "tool definition" do
    it "requires only user_id" do
      schema = described_class.input_schema_value.to_h
      expect(schema[:required]).to eq(["user_id"])
    end
  end
end
