# frozen_string_literal: true

require "spec_helper"
require "llmemory/mcp"

RSpec.describe Llmemory::MCP::Tools::MemoryAddMessage do
  before do
    Llmemory.reset_configuration!
    Llmemory.configuration.short_term_store = :memory
    Llmemory.configuration.long_term_store = :memory
    Llmemory.configuration.long_term_type = :file_based
  end

  describe ".call" do
    it "adds a user message" do
      response = described_class.call(
        user_id: "user123",
        role: "user",
        content: "Hello, how are you?"
      )

      expect(response).to be_a(::MCP::Tool::Response)
      expect(response.content.first[:text]).to include("Message added")
      expect(response.content.first[:text]).to include("user")
    end

    it "adds a message to specific session" do
      response = described_class.call(
        user_id: "user123",
        session_id: "my_session",
        role: "assistant",
        content: "I'm doing well!"
      )

      expect(response.content.first[:text]).to include("my_session")
    end

    it "handles errors gracefully" do
      allow(Llmemory::Memory).to receive(:new).and_raise(StandardError.new("Error"))

      response = described_class.call(
        user_id: "user123",
        role: "user",
        content: "test"
      )

      expect(response.instance_variable_get(:@error)).to be true
    end
  end

  describe "tool definition" do
    it "requires user_id, role, and content" do
      schema = described_class.input_schema_value.to_h
      expect(schema[:required]).to include("user_id")
      expect(schema[:required]).to include("role")
      expect(schema[:required]).to include("content")
    end

    it "has role enum" do
      schema = described_class.input_schema_value.to_h
      expect(schema[:properties][:role][:enum]).to eq(["user", "assistant", "system", "tool", "tool_result"])
    end
  end
end
