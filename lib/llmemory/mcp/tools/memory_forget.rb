# frozen_string_literal: true

module Llmemory
  module MCP
    module Tools
      class MemoryForget < ::MCP::Tool
        description "Remove entries from a memory by their ids (the ids returned by retrieval / listing tools), recording the removal in the audit log. memory_type: file_based | graph_based | episodic | procedural."

        input_schema(
          properties: {
            user_id: { type: "string", description: "User identifier" },
            memory_type: { type: "string", description: "file_based | graph_based | episodic | procedural" },
            ids: { type: "array", items: { type: "string" }, description: "Entry ids to forget" },
            reason: { type: "string", description: "Optional reason (recorded in audit)" }
          },
          required: ["user_id", "memory_type", "ids"]
        )

        class << self
          def call(user_id:, memory_type:, ids:, reason: nil, server_context: nil)
            memory = build_memory(user_id, memory_type)
            removed = memory.forget(ids: Array(ids), reason: reason)
            ::MCP::Tool::Response.new([{
              type: "text",
              text: "Forgot #{removed} entries from #{memory_type} memory for user #{user_id}."
            }])
          rescue NotImplementedError => e
            ::MCP::Tool::Response.new([{ type: "text", text: "Not supported: #{e.message}" }], error: true)
          rescue => e
            ::MCP::Tool::Response.new([{ type: "text", text: "Error forgetting: #{e.message}" }], error: true)
          end

          private

          def build_memory(user_id, memory_type)
            case memory_type.to_s
            when "file_based"
              Llmemory::LongTerm::FileBased::Memory.new(user_id: user_id)
            when "graph_based"
              Llmemory::LongTerm::GraphBased::Memory.new(user_id: user_id)
            when "episodic"
              Llmemory::LongTerm::Episodic::Memory.new(user_id: user_id)
            when "procedural"
              Llmemory::LongTerm::Procedural::Memory.new(user_id: user_id)
            else
              raise ArgumentError, "Unknown memory_type: #{memory_type} (expected file_based|graph_based|episodic|procedural)"
            end
          end
        end
      end
    end
  end
end
