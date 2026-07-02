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
        usage = if response.respond_to?(:usage)
                  response.usage
                elsif inner_client.respond_to?(:last_usage)
                  inner_client.last_usage
                else
                  Usage.zero
                end
        UsageRecorder.record(user_id: @user_id, usage: usage, operation: :invoke, store: @store)
        response
      end

      def invoke_with_json_schema(prompt, json_schema)
        result = inner_client.invoke_with_json_schema(prompt, json_schema)
        usage = inner_client.respond_to?(:last_usage) ? inner_client.last_usage : Usage.zero
        UsageRecorder.record(user_id: @user_id, usage: usage, operation: :invoke, store: @store)
        result
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
    end
  end
end
