# frozen_string_literal: true

module Llmemory
  module LLM
    class Usage
      attr_reader :input_tokens, :output_tokens, :total_tokens

      def initialize(input_tokens:, output_tokens:, total_tokens: nil)
        @input_tokens = input_tokens.to_i
        @output_tokens = output_tokens.to_i
        @total_tokens = total_tokens.nil? ? (@input_tokens + @output_tokens) : total_tokens.to_i
      end

      def self.zero
        new(input_tokens: 0, output_tokens: 0, total_tokens: 0)
      end

      def +(other)
        self.class.new(
          input_tokens: @input_tokens + other.input_tokens,
          output_tokens: @output_tokens + other.output_tokens,
          total_tokens: @total_tokens + other.total_tokens
        )
      end

      def to_h
        { input_tokens: @input_tokens, output_tokens: @output_tokens, total_tokens: @total_tokens }
      end
    end
  end
end
