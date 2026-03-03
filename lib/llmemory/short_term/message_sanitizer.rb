# frozen_string_literal: true

module Llmemory
  module ShortTerm
    class MessageSanitizer
      def initialize(max_message_chars: nil)
        @max_chars = max_message_chars || Llmemory.configuration.max_message_chars
      end

      def sanitize!(messages)
        return [] if messages.nil? || !messages.is_a?(Array)

        out = []
        expect_tool_result = false

        messages.each do |msg|
          msg = msg.dup
          content = (msg[:content] || msg["content"]).to_s
          role = (msg[:role] || msg["role"]).to_s

          next if content.strip.empty?

          content = content[0, @max_chars] if @max_chars && content.length > @max_chars

          if role == "tool"
            expect_tool_result = true
          elsif role == "tool_result"
            next unless expect_tool_result
            expect_tool_result = false
          else
            expect_tool_result = false
          end

          msg[:content] = content if msg.key?(:content)
          msg["content"] = content if msg.key?("content")
          out << msg
        end

        out
      end
    end
  end
end
