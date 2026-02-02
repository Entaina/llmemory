# frozen_string_literal: true

module Llmemory
  module MCP
    module Tools
      class MemoryConsolidate < ::MCP::Tool
        description "Consolidate current short-term conversation into long-term memory. Extracts facts and observations from the conversation."

        input_schema(
          properties: {
            user_id: { type: "string", description: "User identifier" },
            session_id: { type: "string", description: "Session identifier (default: 'default')" },
            clear_session: { type: "boolean", description: "Clear session after consolidation (default: false)" }
          },
          required: ["user_id"]
        )

        class << self
          def call(user_id:, session_id: nil, clear_session: nil, server_context: nil)
            session = session_id || "default"
            should_clear = clear_session || false

            memory = Llmemory::Memory.new(user_id: user_id, session_id: session)

            messages = memory.messages
            if messages.empty?
              return ::MCP::Tool::Response.new([{
                type: "text",
                text: "No messages to consolidate in session '#{session}'."
              }])
            end

            message_count = messages.size
            memory.consolidate!

            if should_clear
              memory.clear_session!
            end

            response_text = "Consolidated #{message_count} messages from session '#{session}' into long-term memory."
            response_text += "\nSession cleared." if should_clear

            ::MCP::Tool::Response.new([{
              type: "text",
              text: response_text
            }])
          rescue => e
            ::MCP::Tool::Response.new([{
              type: "text",
              text: "Error consolidating memory: #{e.message}"
            }], error: true)
          end
        end
      end
    end
  end
end
