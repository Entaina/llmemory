# frozen_string_literal: true

require "faraday"
require "json"
require "digest"
require_relative "base"

module Llmemory
  module VectorStore
    class OpenAIEmbeddings < Base
      DEFAULT_MODEL = "text-embedding-3-small"
      DEFAULT_DIMS = 1536

      def initialize(api_key: nil, model: nil)
        @api_key = api_key || Llmemory.configuration.llm_api_key
        @model = model || DEFAULT_MODEL
        @cache = {}
        @cache_order = []
      end

      def embed(text)
        return Array.new(DEFAULT_DIMS, 0.0) if text.to_s.strip.empty?

        if Llmemory.configuration.embedding_cache_enabled
          key = cache_key(text)
          return @cache[key].dup if @cache.key?(key)
        end

        result = fetch_embedding(text)

        if Llmemory.configuration.embedding_cache_enabled
          evict_if_needed
          @cache[cache_key(text)] = result.dup
          @cache_order << cache_key(text)
        end

        result
      end

      private

      def cache_key(text)
        Digest::SHA256.hexdigest("#{@model}:#{text.to_s.strip}")
      end

      def evict_if_needed
        max = Llmemory.configuration.embedding_cache_max_entries.to_i
        return if max <= 0 || @cache.size < max

        while @cache_order.any? && @cache.size >= max
          k = @cache_order.shift
          @cache.delete(k)
        end
      end

      def fetch_embedding(text)
        result = nil
        Llmemory::Instrumentation.instrument(:llm_embed, provider: :openai, model: @model, text_chars: text.to_s.length) do
          response = connection.post("embeddings") do |req|
            req.headers["Authorization"] = "Bearer #{@api_key}"
            req.headers["Content-Type"] = "application/json"
            req.body = { input: text.to_s.strip, model: @model }.to_json
          end
          raise Llmemory::LLMError, "OpenAI Embeddings API error: #{response.body}" unless response.success?
          body = response.body.is_a?(Hash) ? response.body : JSON.parse(response.body.to_s)
          result = body.dig("data", 0, "embedding")&.map(&:to_f) || Array.new(DEFAULT_DIMS, 0.0)
        end
        result
      end

      def connection
        @connection ||= Faraday.new(url: "https://api.openai.com/v1") do |f|
          f.request :json
          f.response :json
          f.adapter Faraday.default_adapter
        end
      end

      def store(id:, embedding:, metadata: {})
        raise NotImplementedError, "OpenAIEmbeddings does not store; use a VectorStore backend (e.g. MemoryStore)"
      end

      def search(query_embedding, top_k: 10)
        raise NotImplementedError, "OpenAIEmbeddings does not search; use a VectorStore backend"
      end
    end
  end
end
