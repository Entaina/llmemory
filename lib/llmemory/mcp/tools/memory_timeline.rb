# frozen_string_literal: true

module Llmemory
  module MCP
    module Tools
      class MemoryTimeline < ::MCP::Tool
        description "Get chronological timeline of recent memories and interactions for a user."

        input_schema(
          properties: {
            user_id: { type: "string", description: "User identifier" },
            hours: { type: "integer", description: "Hours to look back (default: 24)" },
            include_messages: { type: "boolean", description: "Include short-term messages (default: true)" }
          },
          required: ["user_id"]
        )

        class << self
          def call(user_id:, hours: nil, include_messages: nil, server_context: nil)
            hours = hours || 24
            include_msgs = include_messages.nil? ? true : include_messages

            timeline = []

            # Get recent items from long-term memory
            storage = build_long_term_storage
            begin
              items = storage.get_items_since(user_id, hours: hours)
              items.each do |item|
                timeline << {
                  type: "fact",
                  timestamp: item[:created_at] || item["created_at"],
                  category: item[:category] || item["category"],
                  content: item[:content] || item["content"]
                }
              end
            rescue NotImplementedError
              # Some storages may not implement get_items_since
            end

            # Get recent messages from short-term
            if include_msgs
              store = build_short_term_store
              sessions = store.list_sessions(user_id: user_id)
              sessions.each do |session_id|
                state = store.load(user_id, session_id)
                next unless state.is_a?(Hash)
                messages = state[:messages] || state["messages"] || []
                messages.each_with_index do |m, idx|
                  timeline << {
                    type: "message",
                    timestamp: state[:updated_at] || Time.now,
                    session_id: session_id,
                    role: m[:role] || m["role"],
                    content: m[:content] || m["content"],
                    order: idx
                  }
                end
              end
            end

            # Sort by timestamp (most recent first)
            timeline.sort_by! { |t| t[:timestamp].to_s }.reverse!

            ::MCP::Tool::Response.new([{
              type: "text",
              text: format_timeline(timeline, hours)
            }])
          rescue => e
            ::MCP::Tool::Response.new([{
              type: "text",
              text: "Error getting timeline: #{e.message}"
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

          def format_timeline(timeline, hours)
            return "No activity in the last #{hours} hours." if timeline.empty?

            output = ["Timeline (last #{hours} hours):\n"]
            timeline.first(20).each do |entry|
              case entry[:type]
              when "fact"
                cat_info = entry[:category] ? "[#{entry[:category]}]" : ""
                output << "- [FACT] #{cat_info} #{truncate(entry[:content], 150)}"
              when "message"
                output << "- [MSG #{entry[:session_id]}] [#{entry[:role]}] #{truncate(entry[:content], 150)}"
              end
            end
            output << "\n(Showing #{[timeline.size, 20].min} of #{timeline.size} entries)"
            output.join("\n")
          end

          def truncate(text, max_length)
            return text.to_s if text.to_s.length <= max_length
            "#{text.to_s[0, max_length]}..."
          end
        end
      end
    end
  end
end
