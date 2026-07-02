# frozen_string_literal: true

module Llmemory
  module LLM
    class Response
      attr_reader :content, :usage

      def initialize(content, usage: Usage.zero)
        @content = content.to_s
        @usage = usage
      end

      def to_s
        @content
      end
    end
  end
end
