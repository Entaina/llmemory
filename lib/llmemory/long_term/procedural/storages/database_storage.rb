# frozen_string_literal: true

require "json"
require "securerandom"
require "time"
require_relative "base"
require_relative "../../../crypto/field_helpers"

module Llmemory
  module LongTerm
    module Procedural
      module Storages
        # PostgreSQL backend. Each skill is stored as a JSONB `data` document
        # (plus id/user_id/created_at and a denormalized search_text), mirroring
        # the file-based DatabaseStorage pattern.
        class DatabaseStorage < Base
          include Llmemory::Crypto::FieldHelpers

          def initialize(database_url: nil, cipher: nil)
            @database_url = database_url || Llmemory.configuration.database_url
            @connection = nil
            @cipher = cipher || Llmemory.build_cipher
          end

          def save_skill(user_id, skill)
            ensure_tables!
            id = skill[:id] || skill["id"] || "skill_#{SecureRandom.hex(8)}"
            data = symbolize(skill).merge(id: id, user_id: user_id)
            data[:created_at] ||= Time.now.utc.iso8601
            search = searchable_text(data)
            name = (data[:name] || data["name"]).to_s
            conn.exec_params(
              "INSERT INTO llmemory_skills (id, user_id, data, search_text, search_tokens, name_det, created_at) " \
              "VALUES ($1, $2, $3::jsonb, $4, $5, $6, $7) " \
              "ON CONFLICT (id) DO UPDATE SET data = $3::jsonb, search_text = $4, search_tokens = $5, name_det = $6",
              [id, user_id, store_data(data), enc(search), search_tokens_for(search), enc_det(name), created_at_value(data)]
            )
            id
          end

          def get_skill(user_id, id)
            ensure_tables!
            rows = conn.exec_params("SELECT data FROM llmemory_skills WHERE user_id = $1 AND id = $2", [user_id, id])
            rows.any? ? parse_data(rows.first["data"]) : nil
          end

          def list_skills(user_id, limit: nil, offset: nil)
            ensure_tables!
            sql = "SELECT data FROM llmemory_skills WHERE user_id = $1 AND archived_at IS NULL ORDER BY created_at DESC"
            sql += " LIMIT #{limit.to_i}" if limit && limit.to_i.positive?
            sql += " OFFSET #{offset.to_i}" if offset && offset.to_i.positive?
            conn.exec_params(sql, [user_id]).map { |r| parse_data(r["data"]) }
          end

          def search_skills(user_id, query)
            ensure_tables!
            tokens = Llmemory::Tokenizer.tokenize(query)
            return conn.exec_params(
              "SELECT data FROM llmemory_skills WHERE user_id = $1 AND archived_at IS NULL ORDER BY created_at DESC",
              [user_id]
            ).map { |r| parse_data(r["data"]) } if tokens.empty?

            suffix, params = blind_token_filter("search_text", query, 2, search_tokens_column: cipher.enabled? ? "search_tokens" : nil)
            rows = conn.exec_params(
              "SELECT data FROM llmemory_skills WHERE user_id = $1 AND archived_at IS NULL#{suffix} ORDER BY created_at DESC",
              [user_id, *params]
            )
            skills = rows.map { |r| parse_data(r["data"]) }
            return skills unless cipher.enabled?

            legacy_rows = conn.exec_params(
              "SELECT data FROM llmemory_skills WHERE user_id = $1 AND archived_at IS NULL AND search_tokens IS NULL",
              [user_id]
            )
            legacy = legacy_rows.map { |r| parse_data(r["data"]) }.select do |skill|
              Llmemory::Tokenizer.matches?(searchable_text(skill), query)
            end
            by_id = {}
            (skills + legacy).each { |skill| by_id[skill[:id] || skill["id"]] = skill }
            by_id.values
          end

          def find_skills_by_name(user_id, name)
            ensure_tables!
            if cipher.enabled?
              rows = conn.exec_params(
                "SELECT data FROM llmemory_skills WHERE user_id = $1 AND archived_at IS NULL AND name_det = $2",
                [user_id, enc_det(name.to_s)]
              )
              indexed = rows.map { |r| parse_data(r["data"]) }
              legacy_rows = conn.exec_params(
                "SELECT data FROM llmemory_skills WHERE user_id = $1 AND archived_at IS NULL AND name_det IS NULL",
                [user_id]
              )
              legacy = legacy_rows.map { |r| parse_data(r["data"]) }.select do |skill|
                (skill[:name] || skill["name"]).to_s == name.to_s
              end
              by_id = {}
              (indexed + legacy).each { |skill| by_id[skill[:id] || skill["id"]] = skill }
              by_id.values
            else
              conn.exec_params(
                "SELECT data FROM llmemory_skills WHERE user_id = $1 AND archived_at IS NULL AND data->>'name' = $2",
                [user_id, name.to_s]
              ).map { |r| parse_data(r["data"]) }
            end
          end

          def record_outcome(user_id, skill_id, success:)
            ensure_tables!
            data = get_skill(user_id, skill_id)
            return nil unless data
            key = success ? :success_count : :failure_count
            data[key] = (data[key] || 0).to_i + 1
            data[:updated_at] = Time.now.utc.iso8601
            search = searchable_text(data)
            name = (data[:name] || data["name"]).to_s
            conn.exec_params(
              "UPDATE llmemory_skills SET data = $3::jsonb, search_text = $4, search_tokens = $5, name_det = $6 WHERE user_id = $1 AND id = $2",
              [user_id, skill_id, store_data(data), enc(search), search_tokens_for(search), enc_det(name)]
            )
            data
          end

          def count_skills(user_id)
            ensure_tables!
            conn.exec_params("SELECT COUNT(*) AS c FROM llmemory_skills WHERE user_id = $1 AND archived_at IS NULL", [user_id]).first["c"].to_i
          end

          def delete_skills(user_id, ids)
            ensure_tables!
            Array(ids).sum do |id|
              conn.exec_params("DELETE FROM llmemory_skills WHERE user_id = $1 AND id = $2", [user_id, id]).cmd_tuples
            end
          end

          def archive_skills(user_id, ids)
            ensure_tables!
            Array(ids).sum do |id|
              conn.exec_params(
                "UPDATE llmemory_skills SET archived_at = NOW() WHERE user_id = $1 AND id = $2 AND archived_at IS NULL",
                [user_id, id]
              ).cmd_tuples
            end
          end

          def expired_skill_ids(user_id, cutoff:)
            ensure_tables!
            conn.exec_params(
              "SELECT id FROM llmemory_skills WHERE user_id = $1 AND archived_at IS NULL AND created_at < $2",
              [user_id, cutoff.iso8601]
            ).map { |r| r["id"] }
          end

          def list_users
            ensure_tables!
            conn.exec("SELECT DISTINCT user_id FROM llmemory_skills").map { |r| r["user_id"] }
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
              CREATE TABLE IF NOT EXISTS llmemory_skills (
                id TEXT NOT NULL PRIMARY KEY,
                user_id TEXT NOT NULL,
                data JSONB NOT NULL DEFAULT '{}'::jsonb,
                search_text TEXT,
                created_at TIMESTAMPTZ NOT NULL,
                archived_at TIMESTAMPTZ
              );
              CREATE INDEX IF NOT EXISTS idx_llmemory_skills_user_id ON llmemory_skills(user_id);
              ALTER TABLE llmemory_skills ADD COLUMN IF NOT EXISTS archived_at TIMESTAMPTZ;
              ALTER TABLE llmemory_skills ADD COLUMN IF NOT EXISTS search_tokens TEXT;
              ALTER TABLE llmemory_skills ADD COLUMN IF NOT EXISTS name_det TEXT;
            SQL
          end

          def token_filter(column, query, start_index)
            blind_token_filter(column, query, start_index, search_tokens_column: cipher.enabled? ? "search_tokens" : nil)
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
            [data[:name], data[:description], data[:body]].compact.join("\n")
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
