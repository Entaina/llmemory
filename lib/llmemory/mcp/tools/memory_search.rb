# frozen_string_literal: true

module Llmemory
  module MCP
    module Tools
      class MemorySearch < ::MCP::Tool
        description "Search through user's memory for relevant information. Returns facts, observations, and context matching the query."

        input_schema(
          properties: {
            query: { type: "string", description: "Search query to find relevant memories" },
            user_id: { type: "string", description: "User identifier" },
            search_type: {
              type: "string",
              enum: ["all", "short_term", "long_term"],
              description: "Where to search: all (default), short_term, or long_term"
            },
            max_results: { type: "integer", description: "Maximum results (default: 10)" }
          },
          required: ["query", "user_id"]
        )

        class << self
          def call(query:, user_id:, search_type: "all", max_results: 10, server_context: nil)
            results = []
            search_type = (search_type || "all").downcase
            max_results = max_results || 10

            if search_type == "all" || search_type == "short_term"
              results.concat(search_short_term(user_id, query, max_results))
            end

            if search_type == "all" || search_type == "long_term"
              results.concat(search_long_term(user_id, query, max_results))
            end

            ::MCP::Tool::Response.new([{
              type: "text",
              text: format_results(results.first(max_results))
            }])
          rescue => e
            ::MCP::Tool::Response.new([{
              type: "text",
              text: "Error searching memory: #{e.message}"
            }], error: true)
          end

          private

          def search_short_term(user_id, query, limit)
            store = build_short_term_store
            sessions = store.list_sessions(user_id: user_id)
            results = []
            query_lower = query.downcase

            sessions.each do |session_id|
              state = store.load(user_id, session_id)
              next unless state.is_a?(Hash)
              messages = state[:messages] || state["messages"] || []
              messages.each do |m|
                content = (m[:content] || m["content"]).to_s
                if content.downcase.include?(query_lower)
                  results << {
                    type: "short_term",
                    session_id: session_id,
                    role: m[:role] || m["role"],
                    content: content
                  }
                end
              end
            end

            results.first(limit)
          end

          def search_long_term(user_id, query, limit)
            storage = build_long_term_storage
            results = []

            items = storage.search_items(user_id, query)
            items.first(limit).each do |item|
              results << {
                type: "long_term_fact",
                category: item[:category] || item["category"],
                content: item[:content] || item["content"],
                created_at: item[:created_at] || item["created_at"]
              }
            end

            results
          end

          def build_short_term_store
            case Llmemory.configuration.short_term_store.to_sym
            when :memory then ShortTerm::Stores::MemoryStore.new
            when :redis then ShortTerm::Stores::RedisStore.new
            when :postgres then ShortTerm::Stores::PostgresStore.new
            when :active_record, :activerecord
              require_relative "../../short_term/stores/active_record_store"
              ShortTerm::Stores::ActiveRecordStore.new
            else
              ShortTerm::Stores::MemoryStore.new
            end
          end

          def build_long_term_storage
            LongTerm::FileBased::Storages.build
          end

          def format_results(results)
            return "No memories found matching the query." if results.empty?

            output = ["Found #{results.size} memories:\n"]
            results.each_with_index do |r, i|
              case r[:type]
              when "short_term"
                output << "#{i + 1}. [Session: #{r[:session_id]}] [#{r[:role]}] #{truncate(r[:content], 200)}"
              when "long_term_fact"
                cat_info = r[:category] ? "[#{r[:category]}]" : ""
                output << "#{i + 1}. #{cat_info} #{truncate(r[:content], 200)}"
              end
            end
            output.join("\n")
          end

          def truncate(text, max_length)
            return text if text.length <= max_length
            "#{text[0, max_length]}..."
          end
        end
      end
    end
  end
end
