# frozen_string_literal: true

module Llmemory
  module MCP
    module Tools
      class MemorySave < ::MCP::Tool
        description "Save a new observation or fact to long-term memory. Use this to remember important information about the user."

        input_schema(
          properties: {
            user_id: { type: "string", description: "User identifier" },
            content: { type: "string", description: "The observation or fact to remember" },
            category: {
              type: "string",
              description: "Category for the memory (e.g., preferences, work, personal). If omitted, will be auto-classified."
            }
          },
          required: ["user_id", "content"]
        )

        class << self
          def call(user_id:, content:, category: nil, server_context: nil)
            storage = build_storage

            # If no category provided, use a default
            cat = category || "observations"

            # Generate a simple resource ID for tracking
            resource_id = "mcp_#{Time.now.to_i}_#{rand(1000)}"

            storage.save_item(
              user_id,
              category: cat,
              content: content,
              source_resource_id: resource_id
            )

            ::MCP::Tool::Response.new([{
              type: "text",
              text: "Memory saved successfully.\nCategory: #{cat}\nContent: #{content}"
            }])
          rescue => e
            ::MCP::Tool::Response.new([{
              type: "text",
              text: "Error saving memory: #{e.message}"
            }], error: true)
          end

          private

          def build_storage
            LongTerm::FileBased::Storages.build
          end
        end
      end
    end
  end
end
