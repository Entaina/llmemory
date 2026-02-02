# frozen_string_literal: true

module Llmemory
  module MCP
    module Tools
      class MemoryTimelineContext < ::MCP::Tool
        description "Get temporal context around a specific memory. Shows N events before and after a given item or timestamp."

        input_schema(
          properties: {
            user_id: { type: "string", description: "User identifier" },
            item_id: { type: "string", description: "ID of the item to get context for (e.g., from search results)" },
            timestamp: { type: "string", description: "ISO timestamp to get context around (alternative to item_id)" },
            before: { type: "integer", description: "Number of items before the target (default: 5)" },
            after: { type: "integer", description: "Number of items after the target (default: 5)" }
          },
          required: ["user_id"]
        )

        class << self
          def call(user_id:, item_id: nil, timestamp: nil, before: nil, after: nil, server_context: nil)
            before_count = before || 5
            after_count = after || 5

            reference = item_id || timestamp
            unless reference
              return ::MCP::Tool::Response.new([{
                type: "text",
                text: "Error: Either item_id or timestamp must be provided"
              }], error: true)
            end

            storage = build_storage
            result = storage.get_items_around(user_id, reference, before: before_count, after: after_count)

            ::MCP::Tool::Response.new([{
              type: "text",
              text: format_context(result, reference)
            }])
          rescue => e
            ::MCP::Tool::Response.new([{
              type: "text",
              text: "Error getting timeline context: #{e.message}"
            }], error: true)
          end

          private

          def build_storage
            if Llmemory.configuration.long_term_type.to_s == "graph_based"
              LongTerm::GraphBased::Storages.build
            else
              LongTerm::FileBased::Storages.build
            end
          end

          def format_context(result, reference)
            output = []
            output << "Timeline Context around '#{reference}':\n"

            if result[:before].empty? && result[:target].nil? && result[:after].empty?
              return "No memories found around reference '#{reference}'"
            end

            # Before section
            output << "BEFORE (#{result[:before].size} items):"
            if result[:before].empty?
              output << "  (no earlier items)"
            else
              result[:before].each do |item|
                output << format_item(item)
              end
            end

            # Target section
            output << "\nTARGET:"
            if result[:target]
              output << format_item(result[:target], highlight: true)
            else
              output << "  (target not found)"
            end

            # After section
            output << "\nAFTER (#{result[:after].size} items):"
            if result[:after].empty?
              output << "  (no later items)"
            else
              result[:after].each do |item|
                output << format_item(item)
              end
            end

            output.join("\n")
          end

          def format_item(item, highlight: false)
            prefix = highlight ? ">>> " : "  - "
            timestamp = format_timestamp(item)
            content = extract_content(item)
            category = extract_category(item)

            cat_info = category ? "[#{category}] " : ""
            "#{prefix}[#{timestamp}] #{cat_info}#{truncate(content, 120)}"
          end

          def format_timestamp(item)
            ts = item[:created_at] || item["created_at"] || item.created_at rescue nil
            return "unknown" unless ts
            ts.respond_to?(:strftime) ? ts.strftime("%Y-%m-%d %H:%M") : ts.to_s[0, 16]
          end

          def extract_content(item)
            # Handle both hash and object representations
            if item.respond_to?(:content)
              item.content
            elsif item.respond_to?(:predicate)
              # Graph-based edge
              "#{item.subject_id} -> #{item.predicate} -> #{item.target_id}"
            else
              item[:content] || item["content"] || item.to_s
            end
          end

          def extract_category(item)
            if item.respond_to?(:category)
              item.category
            else
              item[:category] || item["category"]
            end
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
