# frozen_string_literal: true

module Llmemory
  module MCP
    module Tools
      class MemoryAddMessage < ::MCP::Tool
        description "Add a message to the short-term conversation memory."

        input_schema(
          properties: {
            user_id: { type: "string", description: "User identifier" },
            session_id: { type: "string", description: "Session identifier (default: 'default')" },
            role: { type: "string", enum: ["user", "assistant", "system"], description: "Message role" },
            content: { type: "string", description: "Message content" }
          },
          required: ["user_id", "role", "content"]
        )

        class << self
          def call(user_id:, role:, content:, session_id: nil, server_context: nil)
            session = session_id || "default"

            memory = Llmemory::Memory.new(user_id: user_id, session_id: session)
            memory.add_message(role: role.to_sym, content: content)

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
