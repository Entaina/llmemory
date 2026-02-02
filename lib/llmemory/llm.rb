# frozen_string_literal: true

require_relative "llm/base"
require_relative "llm/openai"
require_relative "llm/anthropic"

module Llmemory
  module LLM
    def self.client(api_key: nil)
      opts = api_key.to_s.empty? ? {} : { api_key: api_key }
      case Llmemory.configuration.llm_provider.to_sym
      when :openai then OpenAI.new(**opts)
      when :anthropic then Anthropic.new(**opts)
      else
        raise Llmemory::ConfigurationError, "Unknown LLM provider: #{Llmemory.configuration.llm_provider}"
      end
    end
  end
end
