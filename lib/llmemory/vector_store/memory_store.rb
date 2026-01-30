# frozen_string_literal: true

require_relative "base"

module Llmemory
  module VectorStore
    class MemoryStore < Base
      def initialize(embedding_provider: nil)
        @entries = {}
        @embedding_provider = embedding_provider
      end

      def embed(text)
        return Array.new(1536, 0.0) unless @embedding_provider&.respond_to?(:embed)
        @embedding_provider.embed(text)
      end

      def store(id:, embedding:, metadata: {}, user_id: nil)
        key = user_id ? "#{user_id}:#{id}" : id.to_s
        @entries[key] = { embedding: embedding.to_a.map(&:to_f), metadata: (metadata || {}).merge("user_id" => user_id) }
        id
      end

      def search(query_embedding, top_k: 10, user_id: nil)
        query = query_embedding.to_a.map(&:to_f)
        return [] if query.empty?
        entries = user_id ? @entries.select { |k, _| k.to_s.start_with?("#{user_id}:") } : @entries
        scores = entries.map do |id, data|
          sim = cosine_similarity(query, data[:embedding])
          { id: id, score: sim, metadata: data[:metadata] }
        end
        scores.sort_by { |s| -s[:score] }.first(top_k)
      end

      def search_by_text(query_text, top_k: 10, user_id: nil)
        return [] unless @embedding_provider&.respond_to?(:embed)
        query_embedding = @embedding_provider.embed(query_text)
        search(query_embedding, top_k: top_k, user_id: user_id)
      end

      private

      def cosine_similarity(a, b)
        return 0.0 if a.size != b.size || a.empty?
        dot = a.zip(b).sum { |x, y| x * y }
        norm_a = Math.sqrt(a.sum { |x| x * x })
        norm_b = Math.sqrt(b.sum { |x| x * x })
        return 0.0 if norm_a.zero? || norm_b.zero?
        dot / (norm_a * norm_b)
      end
    end
  end
end
