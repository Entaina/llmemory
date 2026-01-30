# frozen_string_literal: true

require_relative "base"

module Llmemory
  module ShortTerm
    module Stores
      class MemoryStore < Base
        def initialize
          @store = {}
        end

        def save(user_id, session_id, state)
          key = key_for(user_id, session_id)
          @store[key] = { state: state, updated_at: Time.now }
          true
        end

        def load(user_id, session_id)
          key = key_for(user_id, session_id)
          @store.dig(key, :state)
        end

        def delete(user_id, session_id)
          @store.delete(key_for(user_id, session_id))
          true
        end

        private

        def key_for(user_id, session_id)
          "#{user_id}:#{session_id}"
        end
      end
    end
  end
end
