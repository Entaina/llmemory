# frozen_string_literal: true

require "json"
require "securerandom"
require "time"
require_relative "base"
require_relative "../../../crypto/field_helpers"

module Llmemory
  module LongTerm
    module Episodic
      module Storages
        # PostgreSQL backend. Each episode is stored as a JSONB `data` document
        # (plus id/user_id/created_at and a denormalized search_text for keyword
        # search), mirroring the file-based DatabaseStorage pattern.
        class DatabaseStorage < Base
          include Llmemory::Crypto::FieldHelpers

          def initialize(database_url: nil, cipher: nil)
            @database_url = database_url || Llmemory.configuration.database_url
            @connection = nil
            @cipher = cipher || Llmemory.build_cipher
          end

          def save_episode(user_id, episode)
            ensure_tables!
            id = episode[:id] || episode["id"] || "ep_#{SecureRandom.hex(8)}"
            data = symbolize(episode).merge(id: id, user_id: user_id)
            data[:created_at] ||= Time.now.utc.iso8601
            search = searchable_text(data)
            conn.exec_params(
              "INSERT INTO llmemory_episodes (id, user_id, data, search_text, created_at) " \
              "VALUES ($1, $2, $3::jsonb, $4, $5) " \
              "ON CONFLICT (id) DO UPDATE SET data = $3::jsonb, search_text = $4",
              [id, user_id, store_data(data), enc(search), created_at_value(data)]
            )
            id
          end

          def get_episode(user_id, id)
            ensure_tables!
            rows = conn.exec_params("SELECT data FROM llmemory_episodes WHERE user_id = $1 AND id = $2", [user_id, id])
            rows.any? ? parse_data(rows.first["data"]) : nil
          end

          def list_episodes(user_id, limit: nil, offset: nil)
            ensure_tables!
            sql = "SELECT data FROM llmemory_episodes WHERE user_id = $1 AND archived_at IS NULL ORDER BY created_at DESC"
            sql += " LIMIT #{limit.to_i}" if limit && limit.to_i.positive?
            sql += " OFFSET #{offset.to_i}" if offset && offset.to_i.positive?
            conn.exec_params(sql, [user_id]).map { |r| parse_data(r["data"]) }
          end

          def search_episodes(user_id, query)
            ensure_tables!
            suffix, params = token_filter("search_text", query, 2)
            conn.exec_params(
              "SELECT data FROM llmemory_episodes WHERE user_id = $1 AND archived_at IS NULL#{suffix} ORDER BY created_at DESC",
              [user_id, *params]
            ).map { |r| parse_data(r["data"]) }
          end

          def count_episodes(user_id)
            ensure_tables!
            conn.exec_params("SELECT COUNT(*) AS c FROM llmemory_episodes WHERE user_id = $1 AND archived_at IS NULL", [user_id]).first["c"].to_i
          end

          def delete_episodes(user_id, ids)
            ensure_tables!
            Array(ids).sum do |id|
              conn.exec_params("DELETE FROM llmemory_episodes WHERE user_id = $1 AND id = $2", [user_id, id]).cmd_tuples
            end
          end

          def archive_episodes(user_id, ids)
            ensure_tables!
            Array(ids).sum do |id|
              conn.exec_params(
                "UPDATE llmemory_episodes SET archived_at = NOW() WHERE user_id = $1 AND id = $2 AND archived_at IS NULL",
                [user_id, id]
              ).cmd_tuples
            end
          end

          def expired_episode_ids(user_id, cutoff:)
            ensure_tables!
            conn.exec_params(
              "SELECT id FROM llmemory_episodes WHERE user_id = $1 AND archived_at IS NULL AND created_at < $2",
              [user_id, cutoff.iso8601]
            ).map { |r| r["id"] }
          end

          def list_users
            ensure_tables!
            conn.exec("SELECT DISTINCT user_id FROM llmemory_episodes").map { |r| r["user_id"] }
          end

          private

          def conn
            @connection ||= begin
              require "pg"
              PG.connect(@database_url)
            end
          end

          def ensure_tables!
            conn.exec(<<~SQL)
              CREATE TABLE IF NOT EXISTS llmemory_episodes (
                id TEXT NOT NULL PRIMARY KEY,
                user_id TEXT NOT NULL,
                data JSONB NOT NULL DEFAULT '{}'::jsonb,
                search_text TEXT,
                created_at TIMESTAMPTZ NOT NULL,
                archived_at TIMESTAMPTZ
              );
              CREATE INDEX IF NOT EXISTS idx_llmemory_episodes_user_id ON llmemory_episodes(user_id);
              ALTER TABLE llmemory_episodes ADD COLUMN IF NOT EXISTS archived_at TIMESTAMPTZ;
            SQL
          end

          # OR-of-token LIKE filter (see file-based DatabaseStorage). [""] for an
          # empty query => match all.
          def token_filter(column, query, start_index)
            tokens = Llmemory::Tokenizer.tokenize(query)
            return ["", []] if tokens.empty?
            likes = tokens.each_index.map { |i| "LOWER(#{column}) LIKE $#{start_index + i}" }
            [" AND (#{likes.join(' OR ')})", tokens.map { |t| "%#{t}%" }]
          end

          def parse_data(value)
            if value.is_a?(Hash)
              return value.transform_keys(&:to_sym)
            end

            str = value.to_s
            if cipher.encrypted?(str)
              cipher.decrypt_json(str)
            else
              JSON.parse(str, symbolize_names: true)
            end
          rescue JSON::ParserError
            {}
          end

          def store_data(data)
            if cipher.enabled?
              JSON.generate(enc_json(data))
            else
              JSON.generate(data)
            end
          end

          def symbolize(hash)
            hash.each_with_object({}) { |(k, v), acc| acc[k.to_sym] = v }
          end

          def searchable_text(data)
            parts = [data[:summary], data[:outcome]]
            Array(data[:steps]).each do |s|
              next unless s.is_a?(Hash)
              parts << (s[:observation] || s["observation"])
              parts << (s[:action] || s["action"])
              parts << (s[:result] || s["result"])
            end
            parts.compact.join("\n")
          end

          def created_at_value(data)
            ca = data[:created_at]
            return Time.now.utc.iso8601 if ca.nil?
            ca.respond_to?(:iso8601) ? ca.iso8601 : ca.to_s
          end
        end
      end
    end
  end
end
