# frozen_string_literal: true

require_relative "base"

module Llmemory
  module ShortTerm
    module Stores
      class RedisStore < Base
        def initialize(redis_url: nil)
          @redis_url = redis_url || Llmemory.configuration.redis_url
          @redis = nil
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
          require "json"
          JSON.generate(state)
        end

        def deserialize(data)
          require "json"
          JSON.parse(data, symbolize_names: true)
        end
      end
    end
  end
end
