# frozen_string_literal: true

require "spec_helper"
require "llmemory/mcp"

RSpec.describe Llmemory::MCP::Server do
  before do
    Llmemory.reset_configuration!
    Llmemory.configuration.short_term_store = :memory
    Llmemory.configuration.long_term_store = :memory
    Llmemory.configuration.long_term_type = :file_based
  end

  describe "#initialize" do
    it "creates an MCP server with default name" do
      server = described_class.new
      expect(server.server).to be_a(::MCP::Server)
    end

    it "creates an MCP server with custom name" do
      server = described_class.new(name: "custom-memory")
      expect(server.server).to be_a(::MCP::Server)
    end

    it "registers all expected tools" do
      server = described_class.new
      tools = server.server.instance_variable_get(:@tools)

      # Tools is a hash with tool names as keys
      tool_names = tools.keys

      expect(tool_names).to include("memory_search")
      expect(tool_names).to include("memory_save")
      expect(tool_names).to include("memory_retrieve")
      expect(tool_names).to include("memory_timeline")
      expect(tool_names).to include("memory_timeline_context")
      expect(tool_names).to include("memory_add_message")
      expect(tool_names).to include("memory_consolidate")
      expect(tool_names).to include("memory_stats")
      expect(tool_names).to include("memory_info")
    end

    it "registers exactly 17 tools (9 base + 6 cognitive: SF10 + 2 maintenance: SF20)" do
      server = described_class.new
      tools = server.server.instance_variable_get(:@tools)
      expect(tools.size).to eq(17)
    end

    it "registers the new cognitive tools (SF10)" do
      server = described_class.new
      tool_names = server.server.instance_variable_get(:@tools).keys
      expect(tool_names).to include(
        "memory_episode_record", "memory_episodes",
        "memory_skill_register", "memory_skill_report", "memory_skills",
        "memory_forget"
      )
    end

    it "registers the maintenance tools (SF20)" do
      server = described_class.new
      tool_names = server.server.instance_variable_get(:@tools).keys
      expect(tool_names).to include("memory_mine_skills", "memory_maintain")
    end
  end
end
