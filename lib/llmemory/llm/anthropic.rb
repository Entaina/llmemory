# frozen_string_literal: true

require "faraday"
require "json"
require_relative "base"

module Llmemory
  module LLM
    class Anthropic < Base
      DEFAULT_BASE_URL = "https://api.anthropic.com"

      def initialize(api_key: nil, model: nil, base_url: nil)
        @api_key = api_key || config.llm_api_key || ENV["ANTHROPIC_API_KEY"]
        @model = model || config.llm_model || "claude-3-sonnet-20240229"
        @base_url = base_url || config.llm_base_url || DEFAULT_BASE_URL
      end

      def invoke(prompt)
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
        content = body.dig("content", 0, "text")
        content&.strip || ""
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
