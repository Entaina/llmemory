# frozen_string_literal: true

require "faraday"
require "json"
require_relative "base"
require_relative "http_client"

module Llmemory
  module LLM
    class OpenAI < Base
      include HttpClient
      DEFAULT_BASE_URL = "https://api.openai.com/v1"
      DEFAULT_MODEL = "gpt-4"

      def initialize(api_key: nil, model: nil, base_url: nil)
        super()
        @api_key = api_key || config.llm_api_key
        @model = model || config.llm_model || DEFAULT_MODEL
        @base_url = base_url || config.llm_base_url || DEFAULT_BASE_URL
      end

      def invoke(prompt)
        result = nil
        payload = { provider: :openai, model: @model, prompt_chars: prompt.to_s.length }
        Llmemory::Instrumentation.instrument(:llm_invoke, payload) do
          response = post_with_resilience(connection, "chat/completions") do |req|
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
          content = body.dig("choices", 0, "message", "content")&.strip || ""
          usage = parse_openai_chat_usage(body["usage"])
          record_usage(usage)
          payload.merge!(instrumentation_payload(usage, content))
          result = Response.new(content, usage: usage)
        end
        result
      end

      # Calls the model with response_format json_schema (Structured Outputs).
      # Returns the parsed JSON hash. Use when the model supports structured outputs
      # (e.g. gpt-4o, gpt-4o-mini 2024-08-06 and later).
      def invoke_with_json_schema(prompt, json_schema)
        payload = {
          model: @model,
          messages: [{ role: "user", content: prompt }],
          temperature: 0,
          response_format: {
            type: "json_schema",
            json_schema: {
              strict: true,
              name: json_schema[:name] || "extraction",
              schema: json_schema[:schema] || json_schema["schema"]
            }
          }
        }
        parsed = nil
        instrument_payload = { provider: :openai, model: @model, prompt_chars: prompt.to_s.length }
        Llmemory::Instrumentation.instrument(:llm_invoke, instrument_payload) do
          response = post_with_resilience(connection, "chat/completions") do |req|
            req.body = payload.to_json
            req.headers["Content-Type"] = "application/json"
            req.headers["Authorization"] = "Bearer #{@api_key}"
          end

          raise Llmemory::LLMError, "OpenAI API error: #{response.body}" unless response.success?

          body = response.body.is_a?(Hash) ? response.body : JSON.parse(response.body.to_s)
          content = body.dig("choices", 0, "message", "content")&.strip
          usage = parse_openai_chat_usage(body["usage"])
          record_usage(usage)
          instrument_payload.merge!(instrumentation_payload(usage, content.to_s))
          return {} if content.nil? || content.empty?

          parsed = JSON.parse(content)
        end
        parsed
      rescue JSON::ParserError => e
        raise Llmemory::LLMError, "Failed to parse JSON response: #{e.message}"
      end

      private

      def connection
        @connection ||= build_faraday_connection(@base_url)
      end
    end
  end
end
