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

      attr_reader :last_usage, :model

      def initialize(api_key: nil, model: nil, base_url: nil, dimensions: nil)
        @api_key = api_key || Llmemory.configuration.llm_api_key
        @model = model || DEFAULT_MODEL
        @dimensions = dimensions || DEFAULT_DIMS
        @base_url = base_url || Llmemory.configuration.llm_base_url || "https://api.openai.com/v1"
        @cache = {}
        @cache_order = []
        @last_usage = Llmemory::LLM::Usage.zero
      end

      def dimensions
        @dimensions
      end

      def local?
        false
      end

      def embed(text)
        embed_batch([text]).first
      end

      def embed_batch(texts)
        list = Array(texts).map(&:to_s)
        return [] if list.empty?

        results = list.map do |text|
          if text.strip.empty?
            Array.new(dimensions, 0.0)
          elsif Llmemory.configuration.embedding_cache_enabled && @cache.key?(cache_key(text))
            @last_usage = Llmemory::LLM::Usage.zero
            @cache[cache_key(text)].dup
          else
            :miss
          end
        end

        miss_indices = results.each_index.select { |i| results[i] == :miss }
        if miss_indices.any?
          fetched = fetch_embeddings(miss_indices.map { |i| list[i] })
          miss_indices.each_with_index do |idx, j|
            vec = fetched[j]
            results[idx] = vec
            if Llmemory.configuration.embedding_cache_enabled
              evict_if_needed
              @cache[cache_key(list[idx])] = vec.dup
              @cache_order << cache_key(list[idx])
            end
          end
        end
        results
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

      def fetch_embeddings(texts)
        payload = { provider: :openai, model: @model, text_chars: texts.sum(&:length) }
        vectors = nil
        Llmemory::Instrumentation.instrument(:llm_embed, payload) do
          body_input = { input: texts.map { |t| t.to_s.strip }, model: @model }
          body_input[:dimensions] = @dimensions if @dimensions != DEFAULT_DIMS
          response = post_with_resilience(connection, "embeddings") do |req|
            req.headers["Authorization"] = "Bearer #{@api_key}"
            req.headers["Content-Type"] = "application/json"
            req.body = body_input.to_json
          end
          raise Llmemory::LLMError, "OpenAI Embeddings API error: #{response.body}" unless response.success?
          body = response.body.is_a?(Hash) ? response.body : JSON.parse(response.body.to_s)
          @last_usage = parse_embed_usage(body["usage"])
          payload.merge!(
            input_tokens: @last_usage.input_tokens,
            output_tokens: @last_usage.output_tokens,
            total_tokens: @last_usage.total_tokens
          )
          vectors = Array(body["data"]).sort_by { |row| row["index"] }.map do |row|
            row["embedding"]&.map(&:to_f) || Array.new(dimensions, 0.0)
          end
        end
        vectors
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
