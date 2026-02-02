# frozen_string_literal: true

module Llmemory
  module LLM
    class Base
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
    end
  end
end
