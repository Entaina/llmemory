# frozen_string_literal: true

module Llmemory
  module MCP
    module Tools
      class MemorySkillReport < ::MCP::Tool
        description "Report the outcome of applying a skill (success or failure). Feeds retrieval ranking: proven skills surface higher next time."

        input_schema(
          properties: {
            user_id: { type: "string", description: "User identifier" },
            skill_id: { type: "string", description: "Skill id (from MemorySkillRegister / MemorySkills)" },
            success: { type: "boolean", description: "True if the skill worked; false otherwise" }
          },
          required: ["user_id", "skill_id", "success"]
        )

        class << self
          def call(user_id:, skill_id:, success:, server_context: nil)
            memory = Llmemory::LongTerm::Procedural::Memory.new(user_id: user_id)
            skill = memory.report_outcome(skill_id, success: success == true)
            if skill.nil?
              return ::MCP::Tool::Response.new([{ type: "text", text: "Skill not found: #{skill_id}" }], error: true)
            end

            text = "Outcome recorded for #{skill.name} (#{skill_id}): success #{skill.success_count} / failure #{skill.failure_count} (rate #{format('%.2f', skill.success_rate)})"
            ::MCP::Tool::Response.new([{ type: "text", text: text }])
          rescue => e
            ::MCP::Tool::Response.new([{ type: "text", text: "Error reporting outcome: #{e.message}" }], error: true)
          end
        end
      end
    end
  end
end
