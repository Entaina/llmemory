# frozen_string_literal: true

module Llmemory
  module MCP
    module Tools
      class MemoryMaintain < ::MCP::Tool
        description "Run the cognitive maintenance pass for a user: reflect (episodes -> insights), mine skills (episodes -> procedural), and expire entries past their TTL. Each step is isolated; a failure in one is reported and does not abort the others. Returns a summary report."

        input_schema(
          properties: {
            user_id: { type: "string", description: "User identifier" },
            reflect: { type: "boolean", description: "Distill insights from recent episodes (default true)" },
            mine_skills: { type: "boolean", description: "Mine reusable skills from episodes and register them (default: config.skill_mining_enabled)" },
            expire: { type: "boolean", description: "Soft-archive entries past their TTL (default true)" },
            reflection_window: { type: "integer", description: "Episodes to reflect over (default 10)" },
            mining_window: { type: "integer", description: "Episodes to mine for skills (default 20)" }
          },
          required: ["user_id"]
        )

        class << self
          def call(user_id:, reflect: true, mine_skills: nil, expire: true,
                   reflection_window: nil, mining_window: nil, server_context: nil)
            opts = { reflect: reflect, expire: expire }
            opts[:mine_skills] = mine_skills unless mine_skills.nil?
            opts[:reflection_window] = reflection_window.to_i unless reflection_window.nil?
            opts[:mining_window] = mining_window.to_i unless mining_window.nil?

            report = Llmemory::Maintenance::CognitivePass.run!(user_id, **opts)
            ::MCP::Tool::Response.new([{ type: "text", text: format_report(user_id, report) }])
          rescue => e
            ::MCP::Tool::Response.new([{ type: "text", text: "Error running maintenance pass: #{e.message}" }], error: true)
          end

          private

          def format_report(user_id, report)
            expired = report[:expired] || {}
            lines = [
              "Cognitive pass for #{user_id}:",
              "  insights: #{Array(report[:insights]).size}",
              "  skills mined: #{Array(report[:mined]).size}",
              "  expired: episodic=#{expired[:episodic] || 0} procedural=#{expired[:procedural] || 0}"
            ]
            errors = report[:errors] || {}
            lines << "  errors: #{errors.map { |k, v| "#{k}: #{v}" }.join('; ')}" unless errors.empty?
            lines.join("\n")
          end
        end
      end
    end
  end
end
