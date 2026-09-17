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

      def trace_store_instance
        @trace_store_instance ||= ZeroMem::Storages.build
      end

      def build_memory(user_id:, session_id: "default", trace_store: nil, memory_mode: nil)
        mode = memory_mode || Llmemory.configuration.memory_mode
        store = trace_store
        store = trace_store_instance if store.nil? && ZeroMem::Mode.zero_mem_enabled?(mode)
        Llmemory::Memory.new(
          user_id: user_id,
          session_id: session_id,
          trace_store: store,
          memory_mode: mode
        )
      end
    end
  end
end
