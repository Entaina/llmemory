# frozen_string_literal: true

require "mcp"
require_relative "tools/memory_search"
require_relative "tools/memory_save"
require_relative "tools/memory_retrieve"
require_relative "tools/memory_timeline"
require_relative "tools/memory_add_message"
require_relative "tools/memory_consolidate"
require_relative "tools/memory_stats"
require_relative "tools/memory_info"
require_relative "tools/memory_timeline_context"

module Llmemory
  module MCP
    class Server
      attr_reader :server

      def initialize(name: "llmemory", version: nil)
        @server = ::MCP::Server.new(
          name: name,
          version: version || Llmemory::VERSION,
          instructions: instructions_text,
          tools: all_tools
        )
      end

      def run_stdio
        transport = ::MCP::Server::Transports::StdioTransport.new(@server)
        transport.open
      end

      private

      def all_tools
        [
          Tools::MemorySearch,
          Tools::MemorySave,
          Tools::MemoryRetrieve,
          Tools::MemoryTimeline,
          Tools::MemoryTimelineContext,
          Tools::MemoryAddMessage,
          Tools::MemoryConsolidate,
          Tools::MemoryStats,
          Tools::MemoryInfo
        ]
      end

      def instructions_text
        <<~INSTRUCTIONS
          llmemory MCP Server - Persistent Memory System for LLM Agents

          This server provides tools to manage persistent memory for users:
          - Search memories by semantic query
          - Save new observations and facts
          - Retrieve context optimized for LLM inference
          - Manage conversation sessions
          - Consolidate conversations into long-term memory

          RECOMMENDED WORKFLOW:
          1. At start of conversation: use memory_retrieve to get relevant context
          2. During conversation: use memory_save for important observations
          3. At end: use memory_consolidate to persist the conversation

          Use memory_info tool for detailed usage guidelines.
        INSTRUCTIONS
      end
    end
  end
end
