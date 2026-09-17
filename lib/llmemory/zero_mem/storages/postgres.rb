# frozen_string_literal: true

require "json"
require_relative "../storage"
require_relative "memory"
require_relative "snapshot_codec"
require_relative "../../crypto/field_helpers"

module Llmemory
  module ZeroMem
    module Storages
      class PostgresStorage
        include Storage
        include Llmemory::Crypto::FieldHelpers

        SNAPSHOT_ID = "default"
        MUTATORS = Storages::FileStorage::MUTATORS

        def initialize(database_url: nil, cipher: nil)
          @database_url = database_url || Llmemory.configuration.database_url || ENV["DATABASE_URL"]
          raise ConfigurationError, "DATABASE_URL required for zero_mem postgres store" if @database_url.to_s.empty?

          require "pg"
          @conn = PG.connect(@database_url)
          @cipher = cipher || Llmemory.build_cipher
          @inner = Memory.new
          ensure_tables!
          load!
        end

        Storage.instance_methods(false).each do |method_name|
          next if MUTATORS.include?(method_name)

          define_method(method_name) do |*args, **kwargs, &block|
            @inner.public_send(method_name, *args, **kwargs, &block)
          end
        end

        MUTATORS.each do |method_name|
          define_method(method_name) do |*args, **kwargs, &block|
            result = @inner.public_send(method_name, *args, **kwargs, &block)
            save!
            result
          end
        end

        private

        def ensure_tables!
          @conn.exec(<<~SQL)
            CREATE TABLE IF NOT EXISTS llmemory_zero_mem_snapshots (
              id TEXT PRIMARY KEY,
              payload TEXT NOT NULL,
              updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
            );
          SQL
        end

        def load!
          result = @conn.exec_params(
            "SELECT payload FROM llmemory_zero_mem_snapshots WHERE id = $1",
            [SNAPSHOT_ID]
          )
          return if result.ntuples.zero?

          raw = dec(result.first["payload"])
          data = JSON.parse(raw, symbolize_names: true)
          SnapshotCodec.load!(@inner, data)
        end

        def save!
          payload = enc(JSON.generate(SnapshotCodec.dump(@inner)))
          @conn.exec_params(
            <<~SQL,
              INSERT INTO llmemory_zero_mem_snapshots (id, payload, updated_at)
              VALUES ($1, $2, NOW())
              ON CONFLICT (id) DO UPDATE SET payload = EXCLUDED.payload, updated_at = NOW()
            SQL
            [SNAPSHOT_ID, payload]
          )
        end
      end
    end
  end
end
