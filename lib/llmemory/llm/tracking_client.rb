# frozen_string_literal: true

require_relative "usage_recorder"

module Llmemory
  module LLM
    # Transparent wrapper that records token usage to the per-user ledger.
    class TrackingClient
      def initialize(inner, user_id:, store: nil, api_key: nil)
        @inner = inner
        @user_id = user_id
        @store = store
        @api_key = api_key
      end

      def invoke(prompt)
        response = inner_client.invoke(prompt)
        record_usage_from_client(:invoke)
        response
      end

      def invoke_with_json_schema(prompt, json_schema)
        return nil unless structured_output_supported?

        result = nil
        begin
          result = inner_client.invoke_with_json_schema(prompt, json_schema)
          result
        ensure
          record_usage_from_client(:invoke) if structured_output_supported?
        end
      end

      def last_usage
        return inner_client.last_usage if inner_client.respond_to?(:last_usage)

        Usage.zero
      end

      def respond_to?(method, include_private = false)
        inner_client.respond_to?(method, include_private) || super
      end

      def method_missing(method, *args, &block)
        if inner_client.respond_to?(method)
          inner_client.public_send(method, *args, &block)
        else
          super
        end
      end

      private

      def inner_client
        @inner_client ||= @inner || Llmemory::LLM.client(api_key: @api_key)
      end

      def structured_output_supported?
        inner_client.class != Llmemory::LLM::Base &&
          inner_client.method(:invoke_with_json_schema).owner != Llmemory::LLM::Base
      end

      def record_usage_from_client(operation)
        usage = inner_client.respond_to?(:last_usage) ? inner_client.last_usage : Usage.zero
        return if usage.zero?

        UsageRecorder.record(user_id: @user_id, usage: usage, operation: operation, store: @store)
      end
    end
  end
end
