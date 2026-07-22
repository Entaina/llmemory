# frozen_string_literal: true

require "json"
require_relative "../crypto/field_helpers"

module Llmemory
  module Maintenance
    # Populates search_tokens (blind index) and procedural name_det for rows
    # written before encrypted keyword search support. In-place UPDATE only.
    class SearchTokensBackfill
      include Crypto::FieldHelpers

      Result = Struct.new(
        :items, :resources, :episodes, :skills, :skipped, :dry_run,
        keyword_init: true
      ) do
        def total
          items + resources + episodes + skills
        end

        def to_h
          { items: items, resources: resources, episodes: episodes, skills: skills,
            skipped: skipped, dry_run: dry_run, total: total }
        end
      end

      def initialize(cipher: nil, store: nil, dry_run: false, force: false)
        @cipher = cipher || Llmemory.build_cipher
        @store = (store || Llmemory.configuration.long_term_store).to_s.to_sym
        @dry_run = dry_run
        @force = force
      end

      def run(user_id: nil)
        case @store
        when :active_record, :activerecord
          run_active_record(user_id: user_id)
        when :postgres
          run_postgres(user_id: user_id)
        else
          raise ConfigurationError,
                "backfill_search_tokens requires long_term_store :active_record or :postgres (got #{@store.inspect})"
        end
      end

      private

      def run_active_record(user_id: nil)
        require "active_record"
        load_active_record_models!

        result = empty_result
        result.items = backfill_ar_items(user_id)
        result.resources = backfill_ar_resources(user_id)
        result.episodes = backfill_ar_episodes(user_id)
        result.skills = backfill_ar_skills(user_id)
        result
      end

      def run_postgres(user_id: nil)
        result = empty_result
        result.items = backfill_pg_items(user_id)
        result.resources = backfill_pg_resources(user_id)
        result.episodes = backfill_pg_episodes(user_id)
        result.skills = backfill_pg_skills(user_id)
        result
      end

      def empty_result
        Result.new(items: 0, resources: 0, episodes: 0, skills: 0, skipped: 0, dry_run: @dry_run)
      end

      def load_active_record_models!
        LongTerm::FileBased::Storages::ActiveRecordStorage.load_models!
        LongTerm::Episodic::Storages::ActiveRecordStorage.load_models!
        LongTerm::Procedural::Storages::ActiveRecordStorage.load_models!
      end

      # --- ActiveRecord ---

      def backfill_ar_items(user_id)
        model = LongTerm::FileBased::Storages::LlmemoryItem
        return 0 unless model.column_names.include?("search_tokens")

        count = 0
        ar_scope(model, user_id).find_each do |rec|
          tokens = search_tokens_for(dec(rec.content))
          next if tokens.nil?

          rec.update_column(:search_tokens, tokens) unless @dry_run
          count += 1
        end
        count
      end

      def backfill_ar_resources(user_id)
        model = LongTerm::FileBased::Storages::LlmemoryResource
        return 0 unless model.column_names.include?("search_tokens")

        count = 0
        ar_scope(model, user_id).find_each do |rec|
          tokens = search_tokens_for(dec(rec.text))
          next if tokens.nil?

          rec.update_column(:search_tokens, tokens) unless @dry_run
          count += 1
        end
        count
      end

      def backfill_ar_episodes(user_id)
        model = LongTerm::Episodic::Storages::LlmemoryEpisode
        return 0 unless model.column_names.include?("search_tokens")

        count = 0
        ar_scope(model, user_id).find_each do |rec|
          plain = dec(rec.search_text.to_s)
          tokens = search_tokens_for(plain)
          next if tokens.nil?

          rec.update_column(:search_tokens, tokens) unless @dry_run
          count += 1
        end
        count
      end

      def backfill_ar_skills(user_id)
        model = LongTerm::Procedural::Storages::LlmemorySkill
        has_tokens = model.column_names.include?("search_tokens")
        has_name_det = model.column_names.include?("name_det")
        return 0 unless has_tokens || has_name_det

        count = 0
        ar_scope_skills(model, user_id, has_tokens: has_tokens, has_name_det: has_name_det).find_each do |rec|
          updates = {}
          if has_tokens
            plain = dec(rec.search_text.to_s)
            tokens = search_tokens_for(plain)
            updates[:search_tokens] = tokens if tokens
          end
          if has_name_det
            data = decode_json_document(rec.data)
            name = (data[:name] || data["name"]).to_s
            updates[:name_det] = enc_det(name) unless name.empty?
          end
          next if updates.empty?

          if @dry_run
            count += 1
          else
            rec.update_columns(updates)
            count += 1
          end
        end
        count
      end

      def ar_scope(model, user_id)
        scope = model.all
        scope = scope.where(user_id: user_id) if user_id
        scope = scope.where(search_tokens: nil) unless @force
        scope
      end

      def ar_scope_skills(model, user_id, has_tokens:, has_name_det:)
        scope = model.all
        scope = scope.where(user_id: user_id) if user_id
        return scope if @force

        if has_tokens && has_name_det
          scope.where("search_tokens IS NULL OR name_det IS NULL")
        elsif has_tokens
          scope.where(search_tokens: nil)
        elsif has_name_det
          scope.where(name_det: nil)
        else
          scope
        end
      end

      # --- Postgres ---

      def backfill_pg_items(user_id)
        return 0 unless pg_column_exists?("llmemory_items", "search_tokens")

        count = 0
        pg_each_row("llmemory_items", "id, user_id, content", user_id) do |row|
          tokens = search_tokens_for(dec(row["content"]))
          next if tokens.nil?

          pg_update("llmemory_items", row["id"], search_tokens: tokens) unless @dry_run
          count += 1
        end
        count
      end

      def backfill_pg_resources(user_id)
        return 0 unless pg_column_exists?("llmemory_resources", "search_tokens")

        count = 0
        pg_each_row("llmemory_resources", "id, user_id, text", user_id) do |row|
          tokens = search_tokens_for(dec(row["text"]))
          next if tokens.nil?

          pg_update("llmemory_resources", row["id"], search_tokens: tokens) unless @dry_run
          count += 1
        end
        count
      end

      def backfill_pg_episodes(user_id)
        return 0 unless pg_column_exists?("llmemory_episodes", "search_tokens")

        count = 0
        pg_each_row("llmemory_episodes", "id, user_id, search_text", user_id) do |row|
          tokens = search_tokens_for(dec(row["search_text"].to_s))
          next if tokens.nil?

          pg_update("llmemory_episodes", row["id"], search_tokens: tokens) unless @dry_run
          count += 1
        end
        count
      end

      def backfill_pg_skills(user_id)
        has_tokens = pg_column_exists?("llmemory_skills", "search_tokens")
        has_name_det = pg_column_exists?("llmemory_skills", "name_det")
        return 0 unless has_tokens || has_name_det

        count = 0
        sql = "SELECT id, user_id, data, search_text FROM llmemory_skills"
        params = []
        clauses = []
        if user_id
          params << user_id
          clauses << "user_id = $#{params.size}"
        end
        unless @force
          parts = []
          parts << "search_tokens IS NULL" if has_tokens
          parts << "name_det IS NULL" if has_name_det
          clauses << "(#{parts.join(' OR ')})" if parts.any?
        end
        sql += " WHERE #{clauses.join(' AND ')}" unless clauses.empty?

        pg_conn.exec_params(sql, params).each do |row|
          sets = {}
          if has_tokens
            tokens = search_tokens_for(dec(row["search_text"].to_s))
            sets["search_tokens"] = tokens if tokens
          end
          if has_name_det
            data = decode_json_document(row["data"])
            name = (data[:name] || data["name"]).to_s
            sets["name_det"] = enc_det(name) unless name.empty?
          end
          next if sets.empty?

          pg_update_columns("llmemory_skills", row["id"], sets) unless @dry_run
          count += 1
        end
        count
      end

      def pg_each_row(table, columns, user_id)
        sql = "SELECT #{columns} FROM #{table}"
        params = []
        clauses = []
        if user_id
          params << user_id
          clauses << "user_id = $#{params.size}"
        end
        unless @force
          clauses << "search_tokens IS NULL" if pg_column_exists?(table, "search_tokens")
        end
        sql += " WHERE #{clauses.join(' AND ')}" unless clauses.empty?

        pg_conn.exec_params(sql, params).each { |row| yield row }
      end

      def pg_update(table, id, search_tokens:)
        pg_conn.exec_params(
          "UPDATE #{table} SET search_tokens = $1 WHERE id = $2",
          [search_tokens, id]
        )
      end

      def pg_update_columns(table, id, sets)
        return if sets.empty?

        idx = 1
        params = []
        assignments = sets.each_key.map do |col|
          params << sets[col]
          clause = "#{col} = $#{idx}"
          idx += 1
          clause
        end
        params << id
        pg_conn.exec_params(
          "UPDATE #{table} SET #{assignments.join(', ')} WHERE id = $#{idx}",
          params
        )
      end

      def pg_column_exists?(table, column)
        @pg_columns ||= {}
        cache_key = "#{table}.#{column}"
        return @pg_columns[cache_key] if @pg_columns.key?(cache_key)

        rows = pg_conn.exec_params(
          "SELECT 1 FROM information_schema.columns WHERE table_name = $1 AND column_name = $2 LIMIT 1",
          [table, column]
        )
        @pg_columns[cache_key] = rows.any?
      end

      def pg_conn
        @pg_conn ||= begin
          require "pg"
          PG.connect(Llmemory.configuration.database_url)
        end
      end

      def decode_json_document(raw)
        return raw.transform_keys(&:to_sym) if raw.is_a?(Hash)

        str = raw.to_s
        if cipher.encrypted?(str)
          dec_json(str)
        else
          JSON.parse(str, symbolize_names: true)
        end
      rescue JSON::ParserError
        {}
      end
    end
  end
end
