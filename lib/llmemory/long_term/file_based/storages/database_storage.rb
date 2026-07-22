# frozen_string_literal: true

require "json"
require "securerandom"
require_relative "base"
require_relative "../../../crypto/field_helpers"

module Llmemory
  module LongTerm
    module FileBased
      module Storages
        class DatabaseStorage < Base
          include Llmemory::Crypto::FieldHelpers

          def initialize(database_url: nil, cipher: nil)
            @database_url = database_url || Llmemory.configuration.database_url
            @connection = nil
            @cipher = cipher || Llmemory.build_cipher
          end

          def save_resource(user_id, text)
            ensure_tables!
            id = "res_#{SecureRandom.hex(8)}"
            conn.exec_params(
              "INSERT INTO llmemory_resources (id, user_id, text, search_tokens, created_at) VALUES ($1, $2, $3, $4, $5)",
              [id, user_id, enc(text), search_tokens_for(text), Time.now.utc.iso8601]
            )
            id
          end

          def save_item(user_id, category:, content:, source_resource_id:, importance: 0.7, provenance: nil)
            ensure_tables!
            id = "item_#{SecureRandom.hex(8)}"
            conn.exec_params(
              "INSERT INTO llmemory_items (id, user_id, category, content, source_resource_id, importance, provenance, search_tokens, created_at) VALUES ($1, $2, $3, $4, $5, $6, $7::jsonb, $8, $9)",
              [id, user_id, category, enc(content), source_resource_id, importance.to_f, provenance_json(provenance), search_tokens_for(content), Time.now.utc.iso8601]
            )
            id
          end

          def load_category(user_id, category_name)
            ensure_tables!
            result = conn.exec_params(
              "SELECT content FROM llmemory_categories WHERE user_id = $1 AND category_name = $2",
              [user_id, category_name]
            )
            result.any? ? dec(result.first["content"].to_s) : ""
          end

          def save_category(user_id, category_name, content)
            ensure_tables!
            conn.exec_params(
              <<~SQL,
                INSERT INTO llmemory_categories (user_id, category_name, content, updated_at)
                VALUES ($1, $2, $3, $4)
                ON CONFLICT (user_id, category_name)
                DO UPDATE SET content = $3, updated_at = $4
              SQL
              [user_id, category_name, enc(content), Time.now.utc.iso8601]
            )
            true
          end

          def list_categories(user_id)
            ensure_tables!
            conn.exec_params("SELECT category_name FROM llmemory_categories WHERE user_id = $1", [user_id])
              .map { |r| r["category_name"] }
          end

          def search_items(user_id, query)
            ensure_tables!
            tokens = Llmemory::Tokenizer.tokenize(query)
            return get_all_items(user_id) if tokens.empty?

            suffix, params = blind_token_filter("content", query, 2, search_tokens_column: cipher.enabled? ? "search_tokens" : nil)
            rows = conn.exec_params(
              "SELECT id, category, content, source_resource_id, importance, provenance, created_at FROM llmemory_items WHERE user_id = $1#{suffix}",
              [user_id, *params]
            )
            items = rows_to_items(rows)
            return items unless cipher.enabled?

            merge_legacy_search(items, legacy_item_rows(user_id), query, text_key: :content)
          end

          def search_resources(user_id, query)
            ensure_tables!
            tokens = Llmemory::Tokenizer.tokenize(query)
            return get_all_resources(user_id) if tokens.empty?

            suffix, params = blind_token_filter("text", query, 2, search_tokens_column: cipher.enabled? ? "search_tokens" : nil)
            rows = conn.exec_params(
              "SELECT id, text, created_at FROM llmemory_resources WHERE user_id = $1#{suffix}",
              [user_id, *params]
            )
            resources = rows_to_resources(rows)
            return resources unless cipher.enabled?

            merge_legacy_search(resources, legacy_resource_rows(user_id), query, text_key: :text)
          end

          def get_resources_since(user_id, hours:)
            ensure_tables!
            cutoff = (Time.now - (hours * 3600)).utc.iso8601
            rows = conn.exec_params(
              "SELECT id, text, created_at FROM llmemory_resources WHERE user_id = $1 AND created_at >= $2 ORDER BY created_at",
              [user_id, cutoff]
            )
            rows_to_resources(rows)
          end

          def get_items_older_than(user_id, days:)
            ensure_tables!
            cutoff = (Time.now - (days * 86400)).utc.iso8601
            rows = conn.exec_params(
              "SELECT id, category, content, source_resource_id, importance, provenance, created_at FROM llmemory_items WHERE user_id = $1 AND created_at < $2 ORDER BY created_at",
              [user_id, cutoff]
            )
            rows_to_items(rows)
          end

          def get_all_items(user_id)
            ensure_tables!
            rows = conn.exec_params(
              "SELECT id, category, content, source_resource_id, importance, provenance, created_at FROM llmemory_items WHERE user_id = $1 ORDER BY created_at",
              [user_id]
            )
            rows_to_items(rows)
          end

          def get_all_resources(user_id)
            ensure_tables!
            rows = conn.exec_params(
              "SELECT id, text, created_at FROM llmemory_resources WHERE user_id = $1 ORDER BY created_at",
              [user_id]
            )
            rows_to_resources(rows)
          end

          def get_items_since(user_id, hours:)
            ensure_tables!
            cutoff = (Time.now - (hours * 3600)).utc.iso8601
            rows = conn.exec_params(
              "SELECT id, category, content, source_resource_id, importance, provenance, created_at FROM llmemory_items WHERE user_id = $1 AND created_at >= $2 ORDER BY created_at",
              [user_id, cutoff]
            )
            rows_to_items(rows)
          end

          def replace_items(user_id, ids_to_remove, merged_item)
            ensure_tables!
            ids_to_remove.each do |id|
              conn.exec_params("DELETE FROM llmemory_items WHERE user_id = $1 AND id = $2", [user_id, id])
            end
            created_at = merged_item[:created_at] || Time.now
            created_at = created_at.utc.iso8601 if created_at.respond_to?(:utc)
            id = "item_#{SecureRandom.hex(8)}"
            conn.exec_params(
              "INSERT INTO llmemory_items (id, user_id, category, content, source_resource_id, search_tokens, created_at) VALUES ($1, $2, $3, $4, $5, $6, $7)",
              [
                id,
                user_id,
                merged_item[:category],
                enc(merged_item[:content]),
                merged_item[:source_resource_id],
                search_tokens_for(merged_item[:content]),
                created_at
              ]
            )
          end

          def archive_items(user_id, item_ids)
            ensure_tables!
            item_ids.each { |id| conn.exec_params("DELETE FROM llmemory_items WHERE user_id = $1 AND id = $2", [user_id, id]) }
          end

          def archive_resources(user_id, resource_ids)
            ensure_tables!
            resource_ids.each { |id| conn.exec_params("DELETE FROM llmemory_resources WHERE user_id = $1 AND id = $2", [user_id, id]) }
          end

          def list_users
            ensure_tables!
            (conn.exec("SELECT DISTINCT user_id FROM llmemory_resources").map { |r| r["user_id"] } +
             conn.exec("SELECT DISTINCT user_id FROM llmemory_items").map { |r| r["user_id"] } +
             conn.exec("SELECT DISTINCT user_id FROM llmemory_categories").map { |r| r["user_id"] }).uniq
          end

          def list_resources(user_id:, limit: nil, offset: nil)
            ensure_tables!
            sql = "SELECT id, text, created_at FROM llmemory_resources WHERE user_id = $1 ORDER BY created_at"
            sql += " LIMIT #{limit.to_i}" if limit && limit.to_i.positive?
            sql += " OFFSET #{offset.to_i}" if offset && offset.to_i.positive?
            rows = conn.exec_params(sql, [user_id])
            rows_to_resources(rows)
          end

          def list_items(user_id:, category: nil, limit: nil, offset: nil)
            ensure_tables!
            sql = "SELECT id, category, content, source_resource_id, importance, provenance, created_at FROM llmemory_items WHERE user_id = $1"
            params = [user_id]
            if category
              sql += " AND category = $2"
              params << category
            end
            sql += " ORDER BY created_at"
            sql += " LIMIT #{limit.to_i}" if limit && limit.to_i.positive?
            sql += " OFFSET #{offset.to_i}" if offset && offset.to_i.positive?
            rows = params.size == 1 ? conn.exec_params(sql, params) : conn.exec_params(sql, params)
            rows_to_items(rows)
          end

          def count_items(user_id:)
            ensure_tables!
            result = conn.exec_params("SELECT COUNT(*) AS c FROM llmemory_items WHERE user_id = $1", [user_id])
            result.first["c"].to_i
          end

          def get_items_around(user_id, reference, before: 5, after: 5)
            ensure_tables!
            find_around(get_all_items(user_id), reference, before, after)
          end

          def get_resources_around(user_id, reference, before: 5, after: 5)
            ensure_tables!
            find_around(get_all_resources(user_id), reference, before, after)
          end

          private

          def legacy_item_rows(user_id)
            conn.exec_params(
              "SELECT id, category, content, source_resource_id, importance, provenance, created_at FROM llmemory_items WHERE user_id = $1 AND search_tokens IS NULL",
              [user_id]
            )
          end

          def legacy_resource_rows(user_id)
            conn.exec_params(
              "SELECT id, text, created_at FROM llmemory_resources WHERE user_id = $1 AND search_tokens IS NULL",
              [user_id]
            )
          end

          def merge_legacy_search(indexed, legacy_rows, query, text_key:)
            return indexed if legacy_rows.none?

            legacy = if text_key == :content
              rows_to_items(legacy_rows)
            else
              rows_to_resources(legacy_rows)
            end
            legacy_matches = legacy.select { |row| Llmemory::Tokenizer.matches?(row[text_key], query) }
            by_id = {}
            (indexed + legacy_matches).each { |row| by_id[row[:id]] = row }
            by_id.values
          end

          def conn
            @connection ||= begin
              require "pg"
              PG.connect(@database_url)
            end
          end

          def ensure_tables!
            conn.exec(<<~SQL)
              CREATE TABLE IF NOT EXISTS llmemory_resources (
                id TEXT NOT NULL PRIMARY KEY,
                user_id TEXT NOT NULL,
                text TEXT NOT NULL,
                created_at TIMESTAMPTZ NOT NULL
              );
              CREATE INDEX IF NOT EXISTS idx_llmemory_resources_user_id ON llmemory_resources(user_id);
            SQL
            conn.exec(<<~SQL)
              CREATE TABLE IF NOT EXISTS llmemory_items (
                id TEXT NOT NULL PRIMARY KEY,
                user_id TEXT NOT NULL,
                category TEXT NOT NULL,
                content TEXT NOT NULL,
                source_resource_id TEXT,
                importance REAL DEFAULT 0.7,
                provenance JSONB,
                created_at TIMESTAMPTZ NOT NULL
              );
              CREATE INDEX IF NOT EXISTS idx_llmemory_items_user_id ON llmemory_items(user_id);
            SQL
            conn.exec("ALTER TABLE llmemory_items ADD COLUMN IF NOT EXISTS importance REAL DEFAULT 0.7") rescue nil
            conn.exec("ALTER TABLE llmemory_items ADD COLUMN IF NOT EXISTS provenance JSONB") rescue nil
            conn.exec("ALTER TABLE llmemory_items ADD COLUMN IF NOT EXISTS search_tokens TEXT") rescue nil
            conn.exec("ALTER TABLE llmemory_resources ADD COLUMN IF NOT EXISTS search_tokens TEXT") rescue nil
            conn.exec(<<~SQL)
              CREATE TABLE IF NOT EXISTS llmemory_categories (
                user_id TEXT NOT NULL,
                category_name TEXT NOT NULL,
                content TEXT NOT NULL,
                updated_at TIMESTAMPTZ NOT NULL,
                PRIMARY KEY (user_id, category_name)
              );
            SQL
          end

          def rows_to_items(rows)
            rows.map do |r|
              {
                id: r["id"],
                category: r["category"],
                content: dec(r["content"]),
                source_resource_id: r["source_resource_id"],
                importance: (r["importance"] || 0.7).to_f,
                provenance: parse_provenance(r["provenance"]),
                created_at: Time.parse(r["created_at"])
              }
            end
          end

          # Builds an OR-of-token LIKE filter for keyword search. Returns
          # ["" , []] for an empty query (match all). Tokens are [a-z0-9]{2,} so
          # they carry no LIKE wildcards.
          def token_filter(column, query, start_index)
            blind_token_filter(column, query, start_index)
          end

          def parse_provenance(value)
            return nil if value.nil? || value.to_s.strip.empty?
            return value.transform_keys(&:to_sym) if value.is_a?(Hash)
            return dec_json(value) if value.is_a?(String) && cipher.encrypted?(value)

            JSON.parse(value, symbolize_names: true)
          rescue JSON::ParserError
            nil
          end

          def provenance_json(provenance)
            return nil unless provenance
            if cipher.enabled?
              JSON.generate(enc_json(provenance))
            else
              JSON.generate(provenance)
            end
          end

          def rows_to_resources(rows)
            rows.map do |r|
              {
                id: r["id"],
                text: dec(r["text"]),
                created_at: Time.parse(r["created_at"])
              }
            end
          end
        end
      end
    end
  end
end
