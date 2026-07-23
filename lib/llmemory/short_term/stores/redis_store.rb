# frozen_string_literal: true

require_relative "base"
require_relative "../../crypto/field_helpers"
require_relative "key_codec"
require_relative "../session_lifecycle"

module Llmemory
  module ShortTerm
    module Stores
      class RedisStore < Base
        include Llmemory::Crypto::FieldHelpers

        KEY_PREFIX = "llmemory:checkpoint"
        MAX_CAS_RETRIES = 5

        def initialize(redis_url: nil, cipher: nil)
          @redis_url = redis_url || Llmemory.configuration.redis_url
          @redis = nil
          @cipher = cipher || Llmemory.build_cipher
          @conn_mutex = Mutex.new
        end

        def save(user_id, session_id, state)
          with_redis do |client|
            key = key_for(user_id, session_id)
            payload = serialize(state)
            if pseudo_session?(session_id)
              client.set(key, payload)
            else
              client.set(key, payload, ex: session_ttl_seconds)
            end
          end
          true
        end

        def load(user_id, session_id)
          with_redis do |client|
            data = client.get(key_for(user_id, session_id))
            data ? deserialize(data) : nil
          end
        end

        def delete(user_id, session_id)
          with_redis { |client| client.del(key_for(user_id, session_id)) }
          true
        end

        def update(user_id, session_id, &block)
          key = key_for(user_id, session_id)
          retries = 0

          loop do
            result = with_redis do |client|
              client.watch(key) do
                raw = client.get(key)
                current = raw ? deserialize(raw) : nil
                new_state = yield(current)
                next new_state if new_state.nil?

                payload = serialize(new_state)
                if pseudo_session?(session_id)
                  client.multi { |multi| multi.set(key, payload) }
                else
                  client.multi { |multi| multi.set(key, payload, ex: session_ttl_seconds) }
                end
                new_state
              end
            end
            return result unless result.nil?

            retries += 1
            raise Llmemory::StoreError, "Redis CAS update failed after #{MAX_CAS_RETRIES} retries" if retries >= MAX_CAS_RETRIES
          end
        end

        def list_users
          scan_keys("#{KEY_PREFIX}:*").filter_map do |k|
            parts = k.split(":", 4)
            next unless parts.size >= 4

            KeyCodec.decode(parts[2])
          end.uniq
        end

        def list_sessions(user_id:)
          encoded_user = KeyCodec.encode(user_id)
          scan_keys("#{KEY_PREFIX}:#{encoded_user}:*").filter_map do |k|
            parts = k.split(":", 4)
            next unless parts.size >= 4

            KeyCodec.decode(parts[3])
          end
        end

        private

        def with_redis
          @conn_mutex.synchronize do
            yield(redis)
          end
        end

        def redis
          @redis ||= begin
            require "redis"
            Redis.new(url: @redis_url)
          end
        end

        def scan_keys(match)
          keys = []
          with_redis do |client|
            client.scan_each(match: match) { |key| keys << key }
          end
          keys
        end

        def key_for(user_id, session_id)
          "#{KEY_PREFIX}:#{KeyCodec.encode(user_id)}:#{KeyCodec.encode(session_id)}"
        end

        def serialize(state)
          serialize_state(state)
        end

        def deserialize(data)
          deserialize_state(data)
        end

        def pseudo_session?(session_id)
          SessionLifecycle.pseudo_session?(session_id)
        end

        def session_ttl_seconds
          ttl = Llmemory.configuration.redis_session_ttl_seconds
          ttl.positive? ? ttl : 86_400 * 30
        end
      end
    end
  end
end
