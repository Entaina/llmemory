# frozen_string_literal: true

module Llmemory
  module Retrieval
    class ContextAssembler
      def initialize(max_tokens: nil)
        @max_tokens = max_tokens || Llmemory.configuration.max_retrieval_tokens
      end

      def assemble(ranked_memories, max_tokens: nil)
        max_tokens ||= @max_tokens
        selected = []
        token_count = 0

        ranked_memories.each do |memory|
          text = memory[:text] || memory["text"] || ""
          memory_tokens = count_tokens(text)
          break if token_count + memory_tokens > max_tokens

          selected << {
            text: text,
            timestamp: memory[:timestamp] || memory["timestamp"],
            confidence: memory[:temporal_score] || memory[:score] || memory["score"]
          }
          token_count += memory_tokens
        end

        format_context(selected)
      end

      def count_tokens(text)
        (text.to_s.length / 4.0).ceil
      end

      private

      def format_context(memories)
        lines = ["=== RELEVANT MEMORIES ===", ""]
        memories.each do |mem|
          ts = mem[:timestamp]
          ts_str = ts.respond_to?(:iso8601) ? ts.iso8601 : ts.to_s
          conf = mem[:confidence]
          conf_str = conf.is_a?(Numeric) ? format("%.2f", conf) : conf.to_s
          lines << "[#{ts_str}] (confidence: #{conf_str})"
          lines << mem[:text].to_s
          lines << ""
        end
        lines << "=== END MEMORIES ==="
        lines.join("\n")
      end
    end
  end
end
