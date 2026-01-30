# frozen_string_literal: true

module Llmemory
  module LLM
    class Base
      def invoke(prompt)
        raise NotImplementedError, "#{self.class}#invoke must be implemented"
      end

      protected

      def config
        Llmemory.configuration
      end
    end
  end
end
