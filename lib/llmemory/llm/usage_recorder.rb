# frozen_string_literal: true

require_relative "usage_ledger"

module Llmemory
  module LLM
    module UsageRecorder
      module_function

      def record(user_id:, usage:, operation:, store: nil)
        return if user_id.nil? || user_id.to_s.empty?
        return if usage.nil?

        UsageLedger.new(store: store).record(user_id, usage, operation: operation)
      end

      def record_embed_from_store(user_id:, vector_store:, store: nil)
        usage = embed_usage_from(vector_store)
        return unless usage

        record(user_id: user_id, usage: usage, operation: :embed, store: store)
      end

      def embed_usage_from(vector_store)
        return nil unless vector_store

        if vector_store.respond_to?(:last_usage)
          usage = vector_store.last_usage
          return usage unless usage.nil?
        end

        provider = vector_store.instance_variable_get(:@embedding_provider) if vector_store.instance_variable_defined?(:@embedding_provider)
        provider&.last_usage if provider&.respond_to?(:last_usage)
      end
    end
  end
end
