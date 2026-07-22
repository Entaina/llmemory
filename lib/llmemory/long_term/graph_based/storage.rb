# frozen_string_literal: true

require_relative "storages/base"
require_relative "storages/memory_storage"

module Llmemory
  module LongTerm
    module GraphBased
      module Storages
        def self.build(store: nil, cipher: nil)
          resolved_cipher = cipher || Llmemory.build_cipher
          case (store || Llmemory.configuration.long_term_store).to_s.to_sym
          when :memory
            MemoryStorage.new
          when :active_record, :activerecord
            require_relative "storages/active_record_storage"
            ActiveRecordStorage.new(cipher: resolved_cipher)
          else
            store_name = (store || Llmemory.configuration.long_term_store).to_s
            raise Llmemory::ConfigurationError,
                  "graph_based long-term memory supports long_term_store :memory or :active_record; got #{store_name.inspect}"
          end
        end
      end
    end
  end
end
