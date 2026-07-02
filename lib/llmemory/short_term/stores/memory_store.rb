# frozen_string_literal: true

require_relative "base"

module Llmemory
  module ShortTerm
    module Stores
      class MemoryStore < Base
        def initialize(cipher: nil)
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

        def list_users
          @store.keys.map { |k| k.split(":", 2).first }.uniq
        end

        def list_sessions(user_id:)
          prefix = "#{user_id}:"
          @store.keys.select { |k| k.start_with?(prefix) }.map { |k| k.split(":", 2).last }
        end

        private

        def key_for(user_id, session_id)
          "#{user_id}:#{session_id}"
        end
      end
    end
  end
end
