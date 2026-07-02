# frozen_string_literal: true

require_relative "usage"
require_relative "response"

module Llmemory
  module LLM
    class Base
      attr_reader :last_usage

      def initialize(*)
        @last_usage = Usage.zero
      end

      def invoke(prompt)
        raise NotImplementedError, "#{self.class}#invoke must be implemented"
      end

      # Optional: Structured Outputs (JSON schema). Override in providers that support it (e.g. OpenAI).
      # When not overridden, returns nil and callers should fall back to invoke + parse.
      def invoke_with_json_schema(_prompt, _json_schema)
        nil
      end

      protected

      def config
        Llmemory.configuration
      end

      def parse_openai_chat_usage(raw)
        return Usage.zero unless raw.is_a?(Hash)

        Usage.new(
          input_tokens: raw["prompt_tokens"] || raw[:prompt_tokens] || 0,
          output_tokens: raw["completion_tokens"] || raw[:completion_tokens] || 0,
          total_tokens: raw["total_tokens"] || raw[:total_tokens]
        )
      end

      def parse_anthropic_usage(raw)
        return Usage.zero unless raw.is_a?(Hash)

        input = raw["input_tokens"] || raw[:input_tokens] || 0
        output = raw["output_tokens"] || raw[:output_tokens] || 0
        Usage.new(input_tokens: input, output_tokens: output)
      end

      def parse_openai_embed_usage(raw)
        return Usage.zero unless raw.is_a?(Hash)

        total = raw["total_tokens"] || raw[:total_tokens] || 0
        Usage.new(input_tokens: 0, output_tokens: 0, total_tokens: total)
      end

      def record_usage(usage)
        @last_usage = usage
      end

      def instrumentation_payload(usage, content, extra = {})
        usage.to_h.merge(response_chars: content.to_s.length).merge(extra)
      end
    end
  end
end
