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
          text = label_volatile(text) if volatile_memory?(memory)
          memory_tokens = count_tokens(text)
          break if token_count + memory_tokens > max_tokens

          selected << {
            text: text,
            timestamp: memory[:timestamp] || memory["timestamp"],
            confidence: memory[:temporal_score] || memory[:score] || memory["score"],
            volatile: volatile_memory?(memory)
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
        if memories.any?
          top = memories.first
          conf = top[:confidence]
          if conf.is_a?(Numeric) && conf.positive?
            lines << "Most relevant (conf=#{format('%.2f', conf)}):"
            lines << ""
          end
        end
        memories.each do |mem|
          ts = mem[:timestamp]
          ts_str = format_timestamp(ts)
          conf = mem[:confidence]
          conf_str = conf.is_a?(Numeric) ? format("%.2f", conf) : conf.to_s
          lines << "[#{ts_str}] (confidence: #{conf_str})"
          lines << mem[:text].to_s
          lines << ""
        end
        lines << "=== END MEMORIES ==="
        lines.join("\n")
      end

      def volatile_memory?(memory)
        memory[:volatile] == true || memory["volatile"] == true
      end

      def label_volatile_enabled?
        Llmemory.configuration.retrieval_label_volatile
      end

      def label_volatile(text)
        return text unless label_volatile_enabled?

        "[verify live] #{text}"
      end

      def format_timestamp(ts)
        return ts.to_s if ts.nil?

        time = ts.is_a?(Time) ? ts : Llmemory.parse_occurred_at(ts)
        return ts.to_s unless time

        time.utc.strftime("%-d %b %Y")
      end
    end
  end
end
