# frozen_string_literal: true

require_relative "storages/base"
require_relative "storages/memory_storage"

module Llmemory
  module LongTerm
    module GraphBased
      module Storages
        def self.build(store: nil)
          case (store || Llmemory.configuration.long_term_store).to_s.to_sym
          when :memory
            MemoryStorage.new
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
