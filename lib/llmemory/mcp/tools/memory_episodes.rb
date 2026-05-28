# frozen_string_literal: true

module Llmemory
  module MCP
    module Tools
      class MemoryEpisodes < ::MCP::Tool
        description "List recent episodes (episodic memory) for a user. Optionally filter by a keyword query."

        input_schema(
          properties: {
            user_id: { type: "string", description: "User identifier" },
            query: { type: "string", description: "Optional keyword filter" },
            limit: { type: "integer", description: "Max episodes to return (default 10)" }
          },
          required: ["user_id"]
        )

        class << self
          def call(user_id:, query: nil, limit: nil, server_context: nil)
            memory = Llmemory::LongTerm::Episodic::Memory.new(user_id: user_id)
            cap = (limit || 10).to_i
            episodes = if query.to_s.strip.empty?
              memory.recent_episodes(limit: cap)
            else
              memory.search_candidates(query, top_k: cap).filter_map { |c| memory.find_episode(c[:id]) }
            end

            if episodes.empty?
              return ::MCP::Tool::Response.new([{ type: "text", text: "No episodes for user #{user_id}." }])
            end

            lines = episodes.map do |ep|
              "[#{ep.id}] (importance: #{ep.importance}; outcome: #{ep.outcome || 'n/a'}) #{ep.summary || ep.searchable_text[0, 120]}"
            end
            ::MCP::Tool::Response.new([{ type: "text", text: lines.join("\n") }])
          rescue => e
            ::MCP::Tool::Response.new([{ type: "text", text: "Error listing episodes: #{e.message}" }], error: true)
          end
        end
      end
    end
  end
end
