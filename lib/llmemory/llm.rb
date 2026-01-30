# frozen_string_literal: true

require_relative "llm/base"
require_relative "llm/openai"
require_relative "llm/anthropic"

module Llmemory
  module LLM
    def self.client
      case Llmemory.configuration.llm_provider.to_sym
      when :openai then OpenAI.new
      when :anthropic then Anthropic.new
      else
        raise Llmemory::ConfigurationError, "Unknown LLM provider: #{Llmemory.configuration.llm_provider}"
      end
    end
  end
end
