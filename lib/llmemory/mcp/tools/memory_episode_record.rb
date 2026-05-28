# frozen_string_literal: true

module Llmemory
  module MCP
    module Tools
      class MemoryEpisodeRecord < ::MCP::Tool
        description "Record an experience (episodic memory): a trajectory of steps with an optional summary, outcome and importance. Use to remember what just happened so it can be retrieved or distilled into knowledge later."

        input_schema(
          properties: {
            user_id: { type: "string", description: "User identifier" },
            steps: {
              type: "array",
              description: "Ordered list of steps (objects with observation/action/result)",
              items: {
                type: "object",
                properties: {
                  observation: { type: "string" },
                  action: { type: "string" },
                  result: { type: "string" }
                }
              }
            },
            summary: { type: "string", description: "Optional summary (derived from steps if omitted)" },
            outcome: { type: "string", description: "Outcome label, e.g. 'success', 'failure', 'recovered'" },
            importance: { type: "number", description: "Importance 0-1 (default 0.5)" }
          },
          required: ["user_id", "steps"]
        )

        class << self
          def call(user_id:, steps:, summary: nil, outcome: nil, importance: nil, server_context: nil)
            memory = Llmemory::LongTerm::Episodic::Memory.new(user_id: user_id)
            id = memory.record_episode(
              steps: Array(steps),
              summary: summary,
              outcome: outcome,
              importance: importance.nil? ? 0.5 : importance.to_f
            )
            ::MCP::Tool::Response.new([{ type: "text", text: "Episode recorded: #{id}" }])
          rescue => e
            ::MCP::Tool::Response.new([{ type: "text", text: "Error recording episode: #{e.message}" }], error: true)
          end
        end
      end
    end
  end
end
