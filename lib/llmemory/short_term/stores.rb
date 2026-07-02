# frozen_string_literal: true

require_relative "stores/base"
require_relative "stores/memory_store"
require_relative "stores/redis_store"
require_relative "stores/postgres_store"

module Llmemory
  module ShortTerm
    module Stores
      # Single source of truth for selecting a short-term store backend.
      # Shared by Checkpoint, SessionLifecycle and WorkingMemory.
      def self.build(store_type = nil, cipher: nil)
        resolved_cipher = cipher || Llmemory.build_cipher
        case (store_type || Llmemory.configuration.short_term_store).to_sym
        when :memory then MemoryStore.new(cipher: resolved_cipher)
        when :redis then RedisStore.new(cipher: resolved_cipher)
        when :postgres then PostgresStore.new(cipher: resolved_cipher)
        when :active_record, :activerecord
          require_relative "stores/active_record_store"
          ActiveRecordStore.new(cipher: resolved_cipher)
        else
          MemoryStore.new(cipher: resolved_cipher)
        end
      end
    end
  end
end
