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
        def self.build(store: nil, base_path: nil, database_url: nil)
          case (store || Llmemory.configuration.long_term_store).to_s.to_sym
          when :memory
            MemoryStorage.new
          when :file
            FileStorage.new(base_path: base_path || Llmemory.configuration.long_term_storage_path)
          when :postgres, :database
            DatabaseStorage.new(database_url: database_url || Llmemory.configuration.database_url)
          when :active_record, :activerecord
            require_relative "storages/active_record_storage"
            ActiveRecordStorage.new
          else
            MemoryStorage.new
          end
        end
      end
    end
  end
end
