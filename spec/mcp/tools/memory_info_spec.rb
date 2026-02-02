# frozen_string_literal: true

require "spec_helper"
require "llmemory/mcp"

RSpec.describe Llmemory::MCP::Tools::MemoryInfo do
  describe ".call" do
    it "returns documentation text" do
      response = described_class.call

      expect(response).to be_a(::MCP::Tool::Response)
      text = response.content.first[:text]
      expect(text).to include("llmemory - Memory System for LLM Agents")
      expect(text).to include("Overview")
      expect(text).to include("Recommended Workflow")
      expect(text).to include("Tools Reference")
      expect(text).to include("Best Practices")
    end

    it "mentions all tools in the documentation" do
      response = described_class.call
      text = response.content.first[:text]

      expect(text).to include("memory_search")
      expect(text).to include("memory_save")
      expect(text).to include("memory_retrieve")
      expect(text).to include("memory_timeline")
      expect(text).to include("memory_add_message")
      expect(text).to include("memory_consolidate")
      expect(text).to include("memory_stats")
    end
  end

  describe "tool definition" do
    it "has no required parameters" do
      schema = described_class.input_schema_value.to_h
      expect(schema[:required]).to be_nil
      expect(schema[:properties]).to eq({})
    end
  end
end
