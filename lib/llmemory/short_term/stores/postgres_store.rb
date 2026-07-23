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
          @table_ready = false
          @conn_mutex = Mutex.new
        end

        def save(user_id, session_id, state)
          with_conn do |connection|
            ensure_table!(connection)
            connection.exec_params(
              <<~SQL,
                INSERT INTO llmemory_checkpoints (user_id, session_id, state, updated_at)
                VALUES ($1, $2, $3, $4)
                ON CONFLICT (user_id, session_id)
                DO UPDATE SET state = $3, updated_at = $4
              SQL
              [user_id, session_id, serialize(state), Time.now.utc.iso8601]
            )
          end
          true
        end

        def load(user_id, session_id)
          with_conn do |connection|
            ensure_table!(connection)
            result = connection.exec_params(
              "SELECT state FROM llmemory_checkpoints WHERE user_id = $1 AND session_id = $2",
              [user_id, session_id]
            )
            row = result.first
            row ? deserialize(row["state"]) : nil
          end
        end

        def delete(user_id, session_id)
          with_conn do |connection|
            ensure_table!(connection)
            connection.exec_params(
              "DELETE FROM llmemory_checkpoints WHERE user_id = $1 AND session_id = $2",
              [user_id, session_id]
            )
          end
          true
        end

        def update(user_id, session_id, &block)
          with_conn do |connection|
            ensure_table!(connection)
            connection.transaction do
              result = connection.exec_params(
                "SELECT state FROM llmemory_checkpoints WHERE user_id = $1 AND session_id = $2 FOR UPDATE",
                [user_id, session_id]
              )
              row = result.first
              current = row ? deserialize(row["state"]) : nil
              new_state = yield(current)
              next new_state if new_state.nil?

              connection.exec_params(
                <<~SQL,
                  INSERT INTO llmemory_checkpoints (user_id, session_id, state, updated_at)
                  VALUES ($1, $2, $3, $4)
                  ON CONFLICT (user_id, session_id)
                  DO UPDATE SET state = $3, updated_at = $4
                SQL
                [user_id, session_id, serialize(new_state), Time.now.utc.iso8601]
              )
              new_state
            end
          end
        end

        def list_users
          with_conn do |connection|
            ensure_table!(connection)
            result = connection.exec("SELECT DISTINCT user_id FROM llmemory_checkpoints")
            result.map { |r| r["user_id"] }
          end
        end

        def list_sessions(user_id:)
          with_conn do |connection|
            ensure_table!(connection)
            result = connection.exec_params(
              "SELECT session_id FROM llmemory_checkpoints WHERE user_id = $1",
              [user_id]
            )
            result.map { |r| r["session_id"] }
          end
        end

        private

        def with_conn
          @conn_mutex.synchronize do
            yield(conn)
          end
        end

        def conn
          @connection ||= begin
            require "pg"
            PG.connect(@database_url)
          end
        end

        def ensure_table!(connection)
          return if @table_ready

          connection.exec(<<~SQL)
            CREATE TABLE IF NOT EXISTS llmemory_checkpoints (
              user_id TEXT NOT NULL,
              session_id TEXT NOT NULL,
              state JSONB NOT NULL,
              updated_at TIMESTAMPTZ NOT NULL,
              PRIMARY KEY (user_id, session_id)
            )
          SQL
          @table_ready = true
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
