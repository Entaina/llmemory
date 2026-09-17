# frozen_string_literal: true

require_relative "../store_helpers"

module Llmemory
  module MCP
    module Tools
      class MemoryAddMessage < ::MCP::Tool
        description "Add a message to the short-term conversation memory."

        input_schema(
          properties: {
            user_id: { type: "string", description: "User identifier" },
            session_id: { type: "string", description: "Session identifier (default: 'default')" },
            role: { type: "string", enum: ["user", "assistant", "system", "tool", "tool_result"], description: "Message role" },
            content: { type: "string", description: "Message content" },
            occurred_at: { type: "string", description: "Optional ISO8601 timestamp for trace ingestion" },
            boundary_id: { type: "string", description: "Optional boundary identifier (Zero-Mem)" },
            idempotency_key: { type: "string", description: "Optional idempotency key for trace writes" }
          },
          required: ["user_id", "role", "content"]
        )

        class << self
          def call(user_id:, role:, content:, session_id: nil, occurred_at: nil, boundary_id: nil,
                   idempotency_key: nil, server_context: nil)
            session = session_id || "default"

            memory = StoreHelpers.build_memory(user_id: user_id, session_id: session)
            parsed_time = occurred_at ? Time.parse(occurred_at.to_s) : nil
            memory.add_message(
              role: role.to_sym,
              content: content,
              occurred_at: parsed_time,
              boundary_id: boundary_id,
              idempotency_key: idempotency_key
            )

            ::MCP::Tool::Response.new([{
              type: "text",
              text: "Message added to session '#{session}'.\nRole: #{role}\nContent: #{truncate(content, 100)}"
            }])
          rescue => e
            ::MCP::Tool::Response.new([{
              type: "text",
              text: "Error adding message: #{e.message}"
            }], error: true)
          end

          private

          def truncate(text, max_length)
            return text if text.length <= max_length
            "#{text[0, max_length]}..."
          end
        end
      end
    end
  end
end
