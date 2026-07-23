# frozen_string_literal: true

module Llmemory
  class Configuration
    attr_accessor :llm_provider,
                  :llm_api_key,
                  :llm_model,
                  :llm_base_url,
                  :llm_timeout_seconds,
                  :llm_open_timeout_seconds,
                  :llm_http_retries,
                  :redis_session_ttl_override,
                  :short_term_store,
                  :redis_url,
                  :long_term_type,
                  :long_term_store,
                  :long_term_storage_path,
                  :episodic_vector_enabled,
                  :procedural_vector_enabled,
                  :database_url,
                  :vector_store,
                  :time_decay_half_life_days,
                  :importance_weight,
                  :retrieval_feedback_weight,
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
                  :auto_recall_enabled,
                  :noise_filter_enabled,
                  :noise_filter_min_chars,
                  :flush_once_per_cycle_seconds,
                  :overflow_recovery_enabled,
                  :embedding_cache_enabled,
                  :embedding_cache_max_entries,
                  :max_message_chars,
                  :message_sanitizer_enabled,
                  :ttl_episodic_days,
                  :ttl_procedural_days,
                  :skill_mining_enabled,
                  :encryption_enabled,
                  :encryption_key,
                  :shared_memory_stores,
                  :dashboard_auth,
                  :dashboard_require_auth

    def initialize
      @llm_provider = :openai
      @llm_api_key = ENV["OPENAI_API_KEY"]
      @llm_model = nil # falls back to the active provider's DEFAULT_MODEL
      @llm_base_url = nil
      @llm_timeout_seconds = 60
      @llm_open_timeout_seconds = 10
      @llm_http_retries = 2
      @redis_session_ttl_override = nil
      @short_term_store = :memory
      @redis_url = ENV["REDIS_URL"] || "redis://localhost:6379/0"
      @long_term_type = :file_based
      @long_term_store = :memory
      @long_term_storage_path = ENV["LLMEMORY_STORAGE_PATH"] || "./llmemory_data"
      @episodic_vector_enabled = false
      @procedural_vector_enabled = false
      @ttl_episodic_days = nil
      @ttl_procedural_days = nil
      @skill_mining_enabled = false
      @database_url = ENV["DATABASE_URL"]
      @vector_store = nil
      @time_decay_half_life_days = 30
      @importance_weight = 1.0
      @retrieval_feedback_weight = 0.5
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
      @noise_filter_enabled = false
      @noise_filter_min_chars = 10
      @flush_once_per_cycle_seconds = 60
      @overflow_recovery_enabled = false
      @embedding_cache_enabled = true
      @embedding_cache_max_entries = 10_000
      @max_message_chars = 32_000
      @message_sanitizer_enabled = false
      @encryption_enabled = false
      @encryption_key = ENV["LLMEMORY_ENCRYPTION_KEY"]
      @shared_memory_stores = false
      @dashboard_auth = nil
      @dashboard_require_auth = nil
    end

    def dashboard_require_auth?
      return @dashboard_require_auth unless @dashboard_require_auth.nil?

      defined?(Rails) && Rails.respond_to?(:env) && Rails.env.development? ? false : true
    end

    def redis_session_ttl_seconds
      return @redis_session_ttl_override if @redis_session_ttl_override

      session_prune_after_days.to_i * 86_400
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
      ShortTerm::Stores.reset_shared_singletons! if defined?(ShortTerm::Stores)
      if defined?(LongTerm::FileBased::Storages)
        LongTerm::FileBased::Storages.reset_shared_singletons!
      end
      if defined?(LongTerm::GraphBased::Storages)
        LongTerm::GraphBased::Storages.reset_shared_singletons!
      end
    end

    # Builds a Crypto::Cipher when encryption is enabled and a key is present;
    # otherwise returns Crypto::NullCipher. An explicit non-empty instance key
    # enables encryption even when the global flag is off.
    def build_cipher(key = nil)
      resolved = key.nil? ? configuration.encryption_key : key
      enabled = configuration.encryption_enabled || (!key.nil? && !key.to_s.empty?)
      if enabled && resolved.to_s.empty?
        raise ConfigurationError, "encryption_key cannot be empty when encryption is enabled"
      end

      require_relative "crypto/cipher"
      if enabled
        Crypto::Cipher.new(resolved)
      else
        Crypto::NullCipher.new
      end
    end
  end
end
