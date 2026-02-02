# frozen_string_literal: true

module Llmemory
  module MCP
    module Tools
      class MemoryRetrieve < ::MCP::Tool
        description "Retrieve relevant context from memory optimized for LLM inference. Combines short-term conversation history with relevant long-term memories."

        input_schema(
          properties: {
            query: { type: "string", description: "Context query (e.g., current user message)" },
            user_id: { type: "string", description: "User identifier" },
            session_id: { type: "string", description: "Session identifier (default: 'default')" },
            max_tokens: { type: "integer", description: "Maximum tokens for context (default: 2000)" }
          },
          required: ["query", "user_id"]
        )

        class << self
          def call(query:, user_id:, session_id: nil, max_tokens: nil, server_context: nil)
            session = session_id || "default"
            tokens = max_tokens || 2000

            memory = Llmemory::Memory.new(user_id: user_id, session_id: session)
            context = memory.retrieve(query, max_tokens: tokens)

            if context.to_s.strip.empty?
              ::MCP::Tool::Response.new([{
                type: "text",
                text: "No relevant context found for this query."
              }])
            else
              ::MCP::Tool::Response.new([{
                type: "text",
                text: context
              }])
            end
          rescue => e
            ::MCP::Tool::Response.new([{
              type: "text",
              text: "Error retrieving context: #{e.message}"
            }], error: true)
          end
        end
      end
    end
  end
end
