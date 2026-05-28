# frozen_string_literal: true

require "json"
require "securerandom"
require "time"
require_relative "base"

module Llmemory
  module LongTerm
    module Procedural
      module Storages
        # PostgreSQL backend. Each skill is stored as a JSONB `data` document
        # (plus id/user_id/created_at and a denormalized search_text), mirroring
        # the file-based DatabaseStorage pattern.
        class DatabaseStorage < Base
          def initialize(database_url: nil)
            @database_url = database_url || Llmemory.configuration.database_url
            @connection = nil
          end

          def save_skill(user_id, skill)
            ensure_tables!
            id = skill[:id] || skill["id"] || "skill_#{SecureRandom.hex(8)}"
            data = symbolize(skill).merge(id: id, user_id: user_id)
            data[:created_at] ||= Time.now.utc.iso8601
            conn.exec_params(
              "INSERT INTO llmemory_skills (id, user_id, data, search_text, created_at) " \
              "VALUES ($1, $2, $3::jsonb, $4, $5) " \
              "ON CONFLICT (id) DO UPDATE SET data = $3::jsonb, search_text = $4",
              [id, user_id, JSON.generate(data), searchable_text(data), created_at_value(data)]
            )
            id
          end

          def get_skill(user_id, id)
            ensure_tables!
            rows = conn.exec_params("SELECT data FROM llmemory_skills WHERE user_id = $1 AND id = $2", [user_id, id])
            rows.any? ? parse_data(rows.first["data"]) : nil
          end

          def list_skills(user_id, limit: nil)
            ensure_tables!
            sql = "SELECT data FROM llmemory_skills WHERE user_id = $1 ORDER BY created_at DESC"
            sql += " LIMIT #{limit.to_i}" if limit && limit.to_i.positive?
            conn.exec_params(sql, [user_id]).map { |r| parse_data(r["data"]) }
          end

          def search_skills(user_id, query)
            ensure_tables!
            suffix, params = token_filter("search_text", query, 2)
            conn.exec_params(
              "SELECT data FROM llmemory_skills WHERE user_id = $1#{suffix} ORDER BY created_at DESC",
              [user_id, *params]
            ).map { |r| parse_data(r["data"]) }
          end

          def find_skills_by_name(user_id, name)
            ensure_tables!
            conn.exec_params(
              "SELECT data FROM llmemory_skills WHERE user_id = $1 AND data->>'name' = $2",
              [user_id, name.to_s]
            ).map { |r| parse_data(r["data"]) }
          end

          def record_outcome(user_id, skill_id, success:)
            ensure_tables!
            data = get_skill(user_id, skill_id)
            return nil unless data
            key = success ? :success_count : :failure_count
            data[key] = (data[key] || 0).to_i + 1
            data[:updated_at] = Time.now.utc.iso8601
            conn.exec_params(
              "UPDATE llmemory_skills SET data = $3::jsonb, search_text = $4 WHERE user_id = $1 AND id = $2",
              [user_id, skill_id, JSON.generate(data), searchable_text(data)]
            )
            data
          end

          def count_skills(user_id)
            ensure_tables!
            conn.exec_params("SELECT COUNT(*) AS c FROM llmemory_skills WHERE user_id = $1", [user_id]).first["c"].to_i
          end

          def delete_skills(user_id, ids)
            ensure_tables!
            Array(ids).sum do |id|
              conn.exec_params("DELETE FROM llmemory_skills WHERE user_id = $1 AND id = $2", [user_id, id]).cmd_tuples
            end
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
                created_at TIMESTAMPTZ NOT NULL
              );
              CREATE INDEX IF NOT EXISTS idx_llmemory_skills_user_id ON llmemory_skills(user_id);
            SQL
          end

          def token_filter(column, query, start_index)
            tokens = Llmemory::Tokenizer.tokenize(query)
            return ["", []] if tokens.empty?
            likes = tokens.each_index.map { |i| "LOWER(#{column}) LIKE $#{start_index + i}" }
            [" AND (#{likes.join(' OR ')})", tokens.map { |t| "%#{t}%" }]
          end

          def parse_data(value)
            JSON.parse(value.to_s, symbolize_names: true)
          rescue JSON::ParserError
            {}
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
