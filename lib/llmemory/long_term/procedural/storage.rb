# frozen_string_literal: true

require_relative "storages/base"
require_relative "storages/memory_storage"
require_relative "storages/file_storage"

module Llmemory
  module LongTerm
    module Procedural
      # Backward compatibility: Storage points to the in-memory backend.
      Storage = Storages::MemoryStorage

      module Storages
        def self.build(store: nil, base_path: nil)
          case (store || Llmemory.configuration.long_term_store).to_s.to_sym
          when :memory
            MemoryStorage.new
          when :file
            FileStorage.new(base_path: base_path || Llmemory.configuration.long_term_storage_path)
          when :postgres, :database, :active_record, :activerecord
            raise NotImplementedError,
              "Procedural SQL/ActiveRecord storage is not implemented yet; use :memory or :file " \
              "(or pass an explicit storage instance)."
          else
            MemoryStorage.new
          end
        end
      end
    end
  end
end
