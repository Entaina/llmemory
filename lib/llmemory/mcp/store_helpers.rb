# frozen_string_literal: true

module Llmemory
  module MCP
    # Shared store resolution for MCP tools. Respects global configuration and
    # long_term_type when selecting backends.
    module StoreHelpers
      module_function

      def short_term_store
        ShortTerm::Stores.build
      end

      def long_term_storage
        if graph_based?
          LongTerm::GraphBased::Storages.build
        else
          LongTerm::FileBased::Storages.build
        end
      end

      def long_term_memory(user_id:)
        if graph_based?
          LongTerm::GraphBased::Memory.new(user_id: user_id, storage: long_term_storage)
        else
          LongTerm::FileBased::Memory.new(user_id: user_id, storage: long_term_storage)
        end
      end

      def graph_based?
        Llmemory.configuration.long_term_type.to_sym == :graph_based
      end
    end
  end
end
