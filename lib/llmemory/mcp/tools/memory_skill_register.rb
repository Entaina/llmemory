# frozen_string_literal: true

module Llmemory
  module MCP
    module Tools
      class MemorySkillRegister < ::MCP::Tool
        description "Register a reusable skill (procedural memory): a prompt, template or code snippet the agent can retrieve later. Re-registering the same name auto-increments the version."

        input_schema(
          properties: {
            user_id: { type: "string", description: "User identifier" },
            name: { type: "string", description: "Short identifier (skills with the same name get auto-versioned)" },
            body: { type: "string", description: "The skill content (prompt / template / code)" },
            description: { type: "string", description: "Optional human-readable description" },
            kind: { type: "string", description: "prompt | template | code (default: prompt)" }
          },
          required: ["user_id", "name", "body"]
        )

        class << self
          def call(user_id:, name:, body:, description: nil, kind: nil, server_context: nil)
            memory = Llmemory::LongTerm::Procedural::Memory.new(user_id: user_id)
            id = memory.register_skill(
              name: name, body: body, description: description,
              kind: kind || Llmemory::LongTerm::Procedural::Skill::DEFAULT_KIND
            )
            ::MCP::Tool::Response.new([{ type: "text", text: "Skill registered: #{id} (#{name})" }])
          rescue => e
            ::MCP::Tool::Response.new([{ type: "text", text: "Error registering skill: #{e.message}" }], error: true)
          end
        end
      end
    end
  end
end
