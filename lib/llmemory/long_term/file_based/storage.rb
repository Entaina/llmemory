# frozen_string_literal: true

require_relative "storages/base"
require_relative "storages/memory_storage"
require_relative "storages/file_storage"
require_relative "storages/database_storage"

module Llmemory
  module LongTerm
    module FileBased
      # Backward compatibility: Storage points to in-memory implementation.
      # Use Storages::MemoryStorage, Storages::FileStorage, or Storages::DatabaseStorage explicitly,
      # or build from config via Storages.build.
      Storage = Storages::MemoryStorage

      module Storages
        def self.build(store: nil, base_path: nil, database_url: nil, cipher: nil)
          resolved_cipher = cipher || Llmemory.build_cipher
          store_type = (store || Llmemory.configuration.long_term_store).to_s.to_sym
          case store_type
          when :memory
            if Llmemory.configuration.shared_memory_stores
              shared_memory_storage
            else
              MemoryStorage.new
            end
          when :file
            FileStorage.new(
              base_path: base_path || Llmemory.configuration.long_term_storage_path,
              cipher: resolved_cipher
            )
          when :postgres, :database
            DatabaseStorage.new(
              database_url: database_url || Llmemory.configuration.database_url,
              cipher: resolved_cipher
            )
          when :active_record, :activerecord
            require_relative "storages/active_record_storage"
            ActiveRecordStorage.new(cipher: resolved_cipher)
          else
            MemoryStorage.new
          end
        end

        def self.shared_memory_storage
          @shared_memory_storage ||= MemoryStorage.new
        end

        def self.reset_shared_singletons!
          @shared_memory_storage = nil
        end
      end
    end
  end
end
