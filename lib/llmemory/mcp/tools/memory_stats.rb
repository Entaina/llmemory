# frozen_string_literal: true

module Llmemory
  module MCP
    module Tools
      class MemoryStats < ::MCP::Tool
        description "Get memory statistics for a user including message counts, fact counts, and categories."

        input_schema(
          properties: {
            user_id: { type: "string", description: "User identifier" }
          },
          required: ["user_id"]
        )

        class << self
          def call(user_id:, server_context: nil)
            stats = {
              user_id: user_id,
              short_term: {},
              long_term: {}
            }

            # Short-term stats
            store = build_short_term_store
            sessions = store.list_sessions(user_id: user_id)
            total_messages = 0
            sessions.each do |session_id|
              state = store.load(user_id, session_id)
              next unless state.is_a?(Hash)
              messages = state[:messages] || state["messages"] || []
              total_messages += messages.size
            end
            stats[:short_term] = {
              sessions: sessions.size,
              total_messages: total_messages
            }

            # Long-term stats
            storage = build_long_term_storage
            begin
              item_count = storage.count_items(user_id: user_id)
              categories = storage.list_categories(user_id)
              resources = storage.list_resources(user_id: user_id)
              stats[:long_term] = {
                facts: item_count,
                categories: categories.size,
                category_names: categories,
                resources: resources.size
              }
            rescue => e
              stats[:long_term] = { error: e.message }
            end

            ::MCP::Tool::Response.new([{
              type: "text",
              text: format_stats(stats)
            }])
          rescue => e
            ::MCP::Tool::Response.new([{
              type: "text",
              text: "Error getting stats: #{e.message}"
            }], error: true)
          end

          private

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

          def format_stats(stats)
            output = ["Memory Statistics for user '#{stats[:user_id]}':\n"]

            output << "SHORT-TERM MEMORY:"
            output << "  Sessions: #{stats[:short_term][:sessions]}"
            output << "  Total messages: #{stats[:short_term][:total_messages]}"
            output << ""

            output << "LONG-TERM MEMORY:"
            if stats[:long_term][:error]
              output << "  Error: #{stats[:long_term][:error]}"
            else
              output << "  Facts stored: #{stats[:long_term][:facts]}"
              output << "  Categories: #{stats[:long_term][:categories]}"
              if stats[:long_term][:category_names]&.any?
                output << "  Category names: #{stats[:long_term][:category_names].join(', ')}"
              end
              output << "  Resources: #{stats[:long_term][:resources]}"
            end

            output.join("\n")
          end
        end
      end
    end
  end
end
