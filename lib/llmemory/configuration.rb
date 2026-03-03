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
                  :compact_max_bytes,
                  :memory_flush_enabled,
                  :memory_flush_threshold_tokens,
                  :hybrid_search_enabled,
                  :bm25_weight,
                  :mmr_enabled,
                  :mmr_lambda,
                  :prune_tool_results_enabled,
                  :prune_tool_results_mode,
                  :prune_tool_results_max_bytes,
                  :context_window_tokens,
                  :reserve_tokens,
                  :keep_recent_tokens,
                  :session_idle_minutes,
                  :session_prune_after_days,
                  :session_max_entries_per_user,
                  :daily_logs_enabled,
                  :auto_recall_enabled

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
      @memory_flush_enabled = true
      @memory_flush_threshold_tokens = 4000
      @hybrid_search_enabled = true
      @bm25_weight = 0.3
      @mmr_enabled = false
      @mmr_lambda = 0.7
      @prune_tool_results_enabled = false
      @prune_tool_results_mode = :soft_trim
      @prune_tool_results_max_bytes = 2048
      @context_window_tokens = 128_000
      @reserve_tokens = 16_384
      @keep_recent_tokens = 20_000
      @session_idle_minutes = 60
      @session_prune_after_days = 30
      @session_max_entries_per_user = 500
      @daily_logs_enabled = false
      @auto_recall_enabled = false
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
