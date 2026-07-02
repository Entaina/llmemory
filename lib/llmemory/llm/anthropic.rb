# frozen_string_literal: true

require "faraday"
require "json"
require_relative "base"

module Llmemory
  module LLM
    class Anthropic < Base
      DEFAULT_BASE_URL = "https://api.anthropic.com"
      DEFAULT_MODEL = "claude-sonnet-4-6"

      def initialize(api_key: nil, model: nil, base_url: nil)
        super()
        @api_key = api_key || config.llm_api_key || ENV["ANTHROPIC_API_KEY"]
        @model = model || config.llm_model || DEFAULT_MODEL
        @base_url = base_url || config.llm_base_url || DEFAULT_BASE_URL
      end

      def invoke(prompt)
        result = nil
        payload = { provider: :anthropic, model: @model, prompt_chars: prompt.to_s.length }
        Llmemory::Instrumentation.instrument(:llm_invoke, payload) do
          response = connection.post("v1/messages") do |req|
            req.body = {
              model: @model,
              max_tokens: 1024,
              messages: [{ role: "user", content: prompt }]
            }.to_json
            req.headers["Content-Type"] = "application/json"
            req.headers["x-api-key"] = @api_key
            req.headers["anthropic-version"] = "2023-06-01"
          end

          raise Llmemory::LLMError, "Anthropic API error: #{response.body}" unless response.success?

          body = response.body.is_a?(Hash) ? response.body : JSON.parse(response.body.to_s)
          content = body.dig("content", 0, "text")&.strip || ""
          usage = parse_anthropic_usage(body["usage"])
          record_usage(usage)
          payload.merge!(instrumentation_payload(usage, content))
          result = Response.new(content, usage: usage)
        end
        result
      end

      private

      def connection
        @connection ||= Faraday.new(url: @base_url) do |f|
          f.request :json
          f.response :json
          f.adapter Faraday.default_adapter
        end
      end
    end
  end
end
