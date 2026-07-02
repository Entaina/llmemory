# frozen_string_literal: true

require_relative "base"
require_relative "../../crypto/field_helpers"

module Llmemory
  module ShortTerm
    module Stores
      class RedisStore < Base
        include Llmemory::Crypto::FieldHelpers

        def initialize(redis_url: nil, cipher: nil)
          @redis_url = redis_url || Llmemory.configuration.redis_url
          @redis = nil
          @cipher = cipher || Llmemory.build_cipher
        end

        def save(user_id, session_id, state)
          redis.set(key_for(user_id, session_id), serialize(state), ex: 86400 * 7) # 7 days TTL
          true
        end

        def load(user_id, session_id)
          data = redis.get(key_for(user_id, session_id))
          data ? deserialize(data) : nil
        end

        def delete(user_id, session_id)
          redis.del(key_for(user_id, session_id))
          true
        end

        def list_users
          keys = redis.keys("llmemory:checkpoint:*:*")
          keys.map { |k| k.split(":")[2] }.uniq
        end

        def list_sessions(user_id:)
          keys = redis.keys("llmemory:checkpoint:#{user_id}:*")
          keys.map { |k| k.split(":", 4).last }
        end

        private

        def redis
          @redis ||= begin
            require "redis"
            Redis.new(url: @redis_url)
          end
        end

        def key_for(user_id, session_id)
          "llmemory:checkpoint:#{user_id}:#{session_id}"
        end

        def serialize(state)
          serialize_state(state)
        end

        def deserialize(data)
          deserialize_state(data)
        end
      end
    end
  end
end
