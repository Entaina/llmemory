# frozen_string_literal: true

require "faraday"
require "json"
require "digest"
require_relative "base"
require_relative "../llm/usage"
require_relative "../llm/http_client"

module Llmemory
  module VectorStore
    class OpenAIEmbeddings < Base
      include Llmemory::LLM::HttpClient
      DEFAULT_MODEL = "text-embedding-3-small"
      DEFAULT_DIMS = 1536

      attr_reader :last_usage

      def initialize(api_key: nil, model: nil, base_url: nil)
        @api_key = api_key || Llmemory.configuration.llm_api_key
        @model = model || DEFAULT_MODEL
        @base_url = base_url || Llmemory.configuration.llm_base_url || "https://api.openai.com/v1"
        @cache = {}
        @cache_order = []
        @last_usage = Llmemory::LLM::Usage.zero
      end

      def embed(text)
        return Array.new(DEFAULT_DIMS, 0.0) if text.to_s.strip.empty?

        if Llmemory.configuration.embedding_cache_enabled
          key = cache_key(text)
          if @cache.key?(key)
            @last_usage = Llmemory::LLM::Usage.zero
            return @cache[key].dup
          end
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
        payload = { provider: :openai, model: @model, text_chars: text.to_s.length }
        Llmemory::Instrumentation.instrument(:llm_embed, payload) do
          response = post_with_resilience(connection, "embeddings") do |req|
            req.headers["Authorization"] = "Bearer #{@api_key}"
            req.headers["Content-Type"] = "application/json"
            req.body = { input: text.to_s.strip, model: @model }.to_json
          end
          raise Llmemory::LLMError, "OpenAI Embeddings API error: #{response.body}" unless response.success?
          body = response.body.is_a?(Hash) ? response.body : JSON.parse(response.body.to_s)
          @last_usage = parse_embed_usage(body["usage"])
          payload.merge!(
            input_tokens: @last_usage.input_tokens,
            output_tokens: @last_usage.output_tokens,
            total_tokens: @last_usage.total_tokens
          )
          result = body.dig("data", 0, "embedding")&.map(&:to_f) || Array.new(DEFAULT_DIMS, 0.0)
        end
        result
      end

      def parse_embed_usage(raw)
        return Llmemory::LLM::Usage.zero unless raw.is_a?(Hash)

        total = raw["total_tokens"] || raw[:total_tokens] || 0
        Llmemory::LLM::Usage.new(input_tokens: 0, output_tokens: 0, total_tokens: total)
      end

      def connection
        @connection ||= build_faraday_connection(@base_url)
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
