# frozen_string_literal: true

module Llmemory
  class Configuration
    attr_accessor :llm_provider,
                  :llm_api_key,
                  :llm_model,
                  :llm_base_url,
                  :short_term_store,
                  :redis_url,
                  :long_term_type,
                  :long_term_store,
                  :long_term_storage_path,
                  :database_url,
                  :vector_store,
                  :time_decay_half_life_days,
                  :max_retrieval_tokens,
                  :prune_after_days,
                  :compact_max_bytes

    def initialize
      @llm_provider = :openai
      @llm_api_key = ENV["OPENAI_API_KEY"]
      @llm_model = "gpt-4"
      @llm_base_url = nil
      @short_term_store = :memory
      @redis_url = ENV["REDIS_URL"] || "redis://localhost:6379/0"
      @long_term_type = :file_based
      @long_term_store = :memory
      @long_term_storage_path = ENV["LLMEMORY_STORAGE_PATH"] || "./llmemory_data"
      @database_url = ENV["DATABASE_URL"]
      @vector_store = nil
      @time_decay_half_life_days = 30
      @max_retrieval_tokens = 2000
      @prune_after_days = 90
      @compact_max_bytes = 8192
    end
  end

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield configuration
    end

    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end
