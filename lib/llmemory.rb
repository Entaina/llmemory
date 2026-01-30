# frozen_string_literal: true

require_relative "llmemory/version"
require_relative "llmemory/configuration"
require_relative "llmemory/llm"
require_relative "llmemory/short_term"
require_relative "llmemory/long_term"
require_relative "llmemory/retrieval"
require_relative "llmemory/maintenance"
require_relative "llmemory/extractors"

module Llmemory
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class StoreError < Error; end
  class LLMError < Error; end
end
