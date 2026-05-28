# frozen_string_literal: true

module Llmemory
  module MCP
    module Tools
      class MemoryRetrieve < ::MCP::Tool
        description "Retrieve relevant context from memory optimized for LLM inference. Combines short-term conversation history with relevant long-term memories."

        input_schema(
          properties: {
            query: { type: "string", description: "Context query (e.g., current user message)" },
            user_id: { type: "string", description: "User identifier" },
            session_id: { type: "string", description: "Session identifier (default: 'default')" },
            max_tokens: { type: "integer", description: "Maximum tokens for context (default: 2000)" },
            include_timeline_context: { type: "boolean", description: "Include N items before/after top matches (default: false)" },
            timeline_window: { type: "integer", description: "Number of items before/after for timeline context (default: 3)" }
          },
          required: ["query", "user_id"]
        )

        class << self
          def call(query:, user_id:, session_id: nil, max_tokens: nil, include_timeline_context: nil, timeline_window: nil, server_context: nil)
            session = session_id || "default"
            tokens = max_tokens || 2000
            include_timeline = include_timeline_context == true
            window = timeline_window || 3

            memory = Llmemory::Memory.new(user_id: user_id, session_id: session)
            context = memory.retrieve(query, max_tokens: tokens)

            # Add timeline context if requested
            if include_timeline && !context.to_s.strip.empty?
              timeline_context = fetch_timeline_context(user_id, query, window)
              context = "#{context}\n\n#{timeline_context}" unless timeline_context.empty?
            end

            if context.to_s.strip.empty?
              ::MCP::Tool::Response.new([{
                type: "text",
                text: "No relevant context found for this query."
              }])
            else
              ::MCP::Tool::Response.new([{
                type: "text",
                text: context
              }])
            end
          rescue => e
            ::MCP::Tool::Response.new([{
              type: "text",
              text: "Error retrieving context: #{e.message}"
            }], error: true)
          end

          private

          def fetch_timeline_context(user_id, query, window)
            storage = build_storage
            items = storage.search_items(user_id, query)
            return "" if items.empty?

            # Anchor on the most precise match: keyword search is recall-oriented
            # (tokenized OR), so prefer the item whose content contains the full
            # query verbatim, falling back to the first match.
            top_item = best_match(items, query)
            item_id = top_item[:id] || top_item["id"]
            return "" unless item_id

            result = storage.get_items_around(user_id, item_id, before: window, after: window)
            format_timeline_context(result, item_id)
          rescue
            ""
          end

          def best_match(items, query)
            q = query.to_s.downcase.strip
            return items.first if q.empty?
            items.find { |i| (i[:content] || i["content"]).to_s.downcase.include?(q) } || items.first
          end

          def build_storage
            if Llmemory.configuration.long_term_type.to_s == "graph_based"
              LongTerm::GraphBased::Storages.build
            else
              LongTerm::FileBased::Storages.build
            end
          end

          def format_timeline_context(result, reference)
            return "" if result[:before].empty? && result[:target].nil? && result[:after].empty?

            lines = ["=== TIMELINE CONTEXT ===", ""]
            lines << "Events around match '#{reference}':"
            lines << ""

            result[:before].each do |item|
              lines << "  [BEFORE] #{format_item(item)}"
            end

            if result[:target]
              lines << "  [MATCH]  #{format_item(result[:target])}"
            end

            result[:after].each do |item|
              lines << "  [AFTER]  #{format_item(item)}"
            end

            lines << ""
            lines << "=== END TIMELINE CONTEXT ==="
            lines.join("\n")
          end

          def format_item(item)
            ts = item[:created_at] || item["created_at"]
            ts_str = ts.respond_to?(:strftime) ? ts.strftime("%Y-%m-%d") : ts.to_s[0, 10]
            content = item[:content] || item["content"]
            category = item[:category] || item["category"]
            cat_str = category ? "[#{category}] " : ""
            "#{ts_str} #{cat_str}#{truncate(content, 80)}"
          end

          def truncate(text, max)
            return text.to_s if text.to_s.length <= max
            "#{text.to_s[0, max]}..."
          end
        end
      end
    end
  end
end
