# frozen_string_literal: true

require "json"
require_relative "base"
require_relative "key_codec"

module Llmemory
  module ShortTerm
    module Stores
      class MemoryStore < Base
        def initialize(cipher: nil)
          @store = {}
          @mutexes = Hash.new { |h, k| h[k] = Mutex.new }
        end

        def save(user_id, session_id, state)
          key = key_for(user_id, session_id)
          @mutexes[key].synchronize do
            @store[key] = { state: deep_copy(state), updated_at: Time.now }
          end
          true
        end

        def load(user_id, session_id)
          key = key_for(user_id, session_id)
          @mutexes[key].synchronize do
            deep_copy(@store.dig(key, :state))
          end
        end

        def delete(user_id, session_id)
          key = key_for(user_id, session_id)
          @mutexes[key].synchronize do
            @store.delete(key)
          end
          true
        end

        def update(user_id, session_id, &block)
          key = key_for(user_id, session_id)
          @mutexes[key].synchronize do
            current = deep_copy(@store.dig(key, :state))
            new_state = yield(current)
            unless new_state.nil?
              @store[key] = { state: deep_copy(new_state), updated_at: Time.now }
            end
            deep_copy(new_state)
          end
        end

        def list_users
          @store.keys.map { |k| KeyCodec.split_composite_key(k, parts: 2).first }.uniq
        end

        def list_sessions(user_id:)
          encoded_user = KeyCodec.encode(user_id)
          prefix = "#{encoded_user}#{KeyCodec::SEPARATOR}"
          @store.keys
            .select { |k| k.start_with?(prefix) }
            .map { |k| KeyCodec.split_composite_key(k, parts: 2).last }
        end

        private

        def key_for(user_id, session_id)
          KeyCodec.composite_key(user_id, session_id)
        end

        def deep_copy(value)
          return nil if value.nil?

          Marshal.load(Marshal.dump(value))
        end
      end
    end
  end
end
