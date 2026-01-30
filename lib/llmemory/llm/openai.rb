# frozen_string_literal: true

require "faraday"
require "json"
require_relative "base"

module Llmemory
  module LLM
    class OpenAI < Base
      DEFAULT_BASE_URL = "https://api.openai.com/v1"

      def initialize(api_key: nil, model: nil, base_url: nil)
        @api_key = api_key || config.llm_api_key
        @model = model || config.llm_model
        @base_url = base_url || config.llm_base_url || DEFAULT_BASE_URL
      end

      def invoke(prompt)
        response = connection.post("chat/completions") do |req|
          req.body = {
            model: @model,
            messages: [{ role: "user", content: prompt }],
            temperature: 0.3
          }.to_json
          req.headers["Content-Type"] = "application/json"
          req.headers["Authorization"] = "Bearer #{@api_key}"
        end

        raise Llmemory::LLMError, "OpenAI API error: #{response.body}" unless response.success?

        body = response.body.is_a?(Hash) ? response.body : JSON.parse(response.body.to_s)
        body.dig("choices", 0, "message", "content")&.strip || ""
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
