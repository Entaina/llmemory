# frozen_string_literal: true

module Llmemory
  module MCP
    module Tools
      class MemorySkills < ::MCP::Tool
        description "List registered skills (procedural memory) for a user, ranked by proven utility when a query is given."

        input_schema(
          properties: {
            user_id: { type: "string", description: "User identifier" },
            query: { type: "string", description: "Optional keyword to filter skills" },
            limit: { type: "integer", description: "Max skills to return (default 10)" }
          },
          required: ["user_id"]
        )

        class << self
          def call(user_id:, query: nil, limit: nil, server_context: nil)
            memory = Llmemory::LongTerm::Procedural::Memory.new(user_id: user_id)
            cap = (limit || 10).to_i
            skills = if query.to_s.strip.empty?
              memory.skills(limit: cap)
            else
              memory.search_candidates(query, top_k: cap).filter_map { |c| memory.get_skill(c[:id]) }
            end

            if skills.empty?
              return ::MCP::Tool::Response.new([{ type: "text", text: "No skills for user #{user_id}." }])
            end

            lines = skills.map do |s|
              "[#{s.id}] #{s.name} v#{s.version} (#{s.kind}) — success rate #{format('%.2f', s.success_rate)} (#{s.success_count}/#{s.success_count + s.failure_count})"
            end
            ::MCP::Tool::Response.new([{ type: "text", text: lines.join("\n") }])
          rescue => e
            ::MCP::Tool::Response.new([{ type: "text", text: "Error listing skills: #{e.message}" }], error: true)
          end
        end
      end
    end
  end
end
