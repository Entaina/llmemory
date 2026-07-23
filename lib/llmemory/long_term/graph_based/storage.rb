# frozen_string_literal: true

require_relative "storages/base"
require_relative "storages/memory_storage"

module Llmemory
  module LongTerm
    module GraphBased
      module Storages
        def self.build(store: nil, cipher: nil)
          resolved_cipher = cipher || Llmemory.build_cipher
          store_type = (store || Llmemory.configuration.long_term_store).to_s.to_sym
          case store_type
          when :memory
            if Llmemory.configuration.shared_memory_stores
              shared_memory_storage
            else
              MemoryStorage.new
            end
          when :active_record, :activerecord
            require_relative "storages/active_record_storage"
            ActiveRecordStorage.new(cipher: resolved_cipher)
          else
            store_name = (store || Llmemory.configuration.long_term_store).to_s
            raise Llmemory::ConfigurationError,
                  "graph_based long-term memory supports long_term_store :memory or :active_record; got #{store_name.inspect}"
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
