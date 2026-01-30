# frozen_string_literal: true

require_relative "stores/base"
require_relative "stores/memory_store"
require_relative "stores/redis_store"
require_relative "stores/postgres_store"

module Llmemory
  module ShortTerm
    class Checkpoint
      DEFAULT_SESSION_ID = "default"

      def initialize(user_id:, session_id: DEFAULT_SESSION_ID, store: nil)
        @user_id = user_id
        @session_id = session_id
        @store = store || build_store
      end

      def save_state(state)
        @store.save(@user_id, @session_id, state)
      end

      def restore_state
        @store.load(@user_id, @session_id)
      end

      def clear_state
        @store.delete(@user_id, @session_id)
      end

      private

      def build_store
        case Llmemory.configuration.short_term_store.to_sym
        when :memory then Stores::MemoryStore.new
        when :redis then Stores::RedisStore.new
        when :postgres then Stores::PostgresStore.new
        else
          Stores::MemoryStore.new
        end
      end
    end
  end
end
