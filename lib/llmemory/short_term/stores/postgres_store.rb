# frozen_string_literal: true

require_relative "base"
require_relative "../../crypto/field_helpers"

module Llmemory
  module ShortTerm
    module Stores
      class PostgresStore < Base
        include Llmemory::Crypto::FieldHelpers

        def initialize(database_url: nil, cipher: nil)
          @database_url = database_url || Llmemory.configuration.database_url
          @connection = nil
          @cipher = cipher || Llmemory.build_cipher
        end

        def save(user_id, session_id, state)
          ensure_table!
          conn.exec_params(
            <<~SQL,
              INSERT INTO llmemory_checkpoints (user_id, session_id, state, updated_at)
              VALUES ($1, $2, $3, $4)
              ON CONFLICT (user_id, session_id)
              DO UPDATE SET state = $3, updated_at = $4
            SQL
            [user_id, session_id, serialize(state), Time.now.utc.iso8601]
          )
          true
        end

        def load(user_id, session_id)
          ensure_table!
          result = conn.exec_params(
            "SELECT state FROM llmemory_checkpoints WHERE user_id = $1 AND session_id = $2",
            [user_id, session_id]
          )
          row = result.first
          row ? deserialize(row["state"]) : nil
        end

        def delete(user_id, session_id)
          ensure_table!
          conn.exec_params(
            "DELETE FROM llmemory_checkpoints WHERE user_id = $1 AND session_id = $2",
            [user_id, session_id]
          )
          true
        end

        def list_users
          ensure_table!
          result = conn.exec("SELECT DISTINCT user_id FROM llmemory_checkpoints")
          result.map { |r| r["user_id"] }
        end

        def list_sessions(user_id:)
          ensure_table!
          result = conn.exec_params(
            "SELECT session_id FROM llmemory_checkpoints WHERE user_id = $1",
            [user_id]
          )
          result.map { |r| r["session_id"] }
        end

        private

        def conn
          @connection ||= begin
            require "pg"
            PG.connect(@database_url)
          end
        end

        def ensure_table!
          conn.exec(<<~SQL)
            CREATE TABLE IF NOT EXISTS llmemory_checkpoints (
              user_id TEXT NOT NULL,
              session_id TEXT NOT NULL,
              state JSONB NOT NULL,
              updated_at TIMESTAMPTZ NOT NULL,
              PRIMARY KEY (user_id, session_id)
            )
          SQL
        end

        def serialize(state)
          payload = serialize_state(state)
          cipher.enabled? ? JSON.generate(payload) : payload
        end

        def deserialize(data)
          if data.is_a?(String) && !cipher.encrypted?(data)
            data = JSON.parse(data)
          end
          deserialize_state(data)
        end
      end
    end
  end
end
