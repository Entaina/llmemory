# frozen_string_literal: true

require "faraday"
require "json"
require_relative "base"

module Llmemory
  module VectorStore
    class OpenAIEmbeddings < Base
      DEFAULT_MODEL = "text-embedding-3-small"
      DEFAULT_DIMS = 1536

      def initialize(api_key: nil, model: nil)
        @api_key = api_key || Llmemory.configuration.llm_api_key
        @model = model || DEFAULT_MODEL
      end

      def embed(text)
        return Array.new(DEFAULT_DIMS, 0.0) if text.to_s.strip.empty?
        response = connection.post("/embeddings") do |req|
          req.headers["Authorization"] = "Bearer #{@api_key}"
          req.headers["Content-Type"] = "application/json"
          req.body = { input: text.to_s.strip, model: @model }.to_json
        end
        raise Llmemory::LLMError, "OpenAI Embeddings API error: #{response.body}" unless response.success?
        body = response.body.is_a?(Hash) ? response.body : JSON.parse(response.body.to_s)
        body.dig("data", 0, "embedding")&.map(&:to_f) || Array.new(DEFAULT_DIMS, 0.0)
      end

      def store(id:, embedding:, metadata: {})
        raise NotImplementedError, "OpenAIEmbeddings does not store; use a VectorStore backend (e.g. MemoryStore)"
      end

      def search(query_embedding, top_k: 10)
        raise NotImplementedError, "OpenAIEmbeddings does not search; use a VectorStore backend"
      end

      private

      def connection
        @connection ||= Faraday.new(url: "https://api.openai.com/v1") do |f|
          f.request :json
          f.response :json
          f.adapter Faraday.default_adapter
        end
      end
    end
  end
end
