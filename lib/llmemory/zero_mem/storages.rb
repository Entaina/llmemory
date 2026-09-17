# frozen_string_literal: true

require_relative "storages/memory"

module Llmemory
  module ZeroMem
    module Storages
      def self.build(store: nil, cipher: nil)
        resolved = store || resolve_store
        case resolved.to_sym
        when :memory
          Memory.new
        when :file
          require_relative "storages/file"
          FileStorage.new(cipher: cipher)
        when :postgres
          require_relative "storages/postgres"
          PostgresStorage.new(cipher: cipher)
        when :active_record
          require_relative "storages/active_record"
          ActiveRecordStorage.new(cipher: cipher)
        else
          raise Llmemory::ConfigurationError,
                "Unsupported zero_mem trace store: #{resolved.inspect} " \
                "(use :memory, :file, :postgres, or :active_record)"
        end
      end

      def self.resolve_store
        explicit = Llmemory.configuration.zero_mem_trace_store
        return explicit if explicit && explicit.to_sym != :memory

        case Llmemory.configuration.long_term_store.to_sym
        when :file then :file
        when :postgres then :postgres
        when :active_record, :activerecord then :active_record
        else
          Llmemory.configuration.zero_mem_trace_store || :memory
        end
      end
    end
  end
end
