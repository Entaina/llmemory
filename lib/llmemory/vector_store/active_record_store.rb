# frozen_string_literal: true

require_relative "base"

module Llmemory
  module VectorStore
    # Persists embeddings in llmemory_embeddings (pgvector).
    # Use when long_term_store is :active_record so hybrid search finds persisted embeddings.
    class ActiveRecordStore < Base
      def initialize(embedding_provider: nil)
        self.class.load_model!
        @embedding_provider = embedding_provider
      end

      def self.load_model!
        return if @model_loaded
        require "active_record"
        require_relative "active_record_embedding"
        @model_loaded = true
      end

      def embed(text)
        return Array.new(1536, 0.0) unless @embedding_provider&.respond_to?(:embed)
        @embedding_provider.embed(text)
      end

      def store(id:, embedding:, metadata: {}, user_id: nil)
        return id if user_id.nil? || user_id.to_s.empty?
        text_content = (metadata || {}).dig("text") || (metadata || {}).dig(:text)
        rec = Llmemory::VectorStore::ActiveRecordEmbedding.find_or_initialize_by(
          user_id: user_id.to_s,
          source_type: "edge",
          source_id: id.to_s
        )
        rec.embedding = embedding.to_a.map(&:to_f)
        rec.text_content = text_content
        rec.save!
        id
      end

      def search(query_embedding, top_k: 10, user_id: nil)
        return [] if user_id.nil? || user_id.to_s.empty?
        vec = query_embedding.to_a.map(&:to_f)
        return [] if vec.empty?
        # Sanitize vector for pgvector (only floats allowed)
        sanitized_vec = vec.map { |v| v.finite? ? v : 0.0 }
        vector_literal = "[#{sanitized_vec.join(',')}]"
        # pgvector cosine distance <=> (0 = same, 2 = opposite); score = 1 - distance for similarity
        scope = Llmemory::VectorStore::ActiveRecordEmbedding.where(user_id: user_id.to_s)
        rows = scope.select(
          Llmemory::VectorStore::ActiveRecordEmbedding.arel_table[Arel.star],
          Arel.sql("(embedding <=> '#{vector_literal}'::vector) AS distance")
        ).order(Arel.sql("embedding <=> '#{vector_literal}'::vector")).limit(top_k)
        rows.map do |r|
          distance = r["distance"] || r.attributes["distance"] || 0.0
          score = (1.0 - distance.to_f).clamp(-1.0, 1.0)
          {
            id: r.source_id,
            score: score,
            metadata: { "text" => r.text_content, "created_at" => r.created_at, "user_id" => r.user_id }
          }
        end
      end

      def search_by_text(query_text, top_k: 10, user_id: nil)
        return [] if user_id.nil? || user_id.to_s.empty?
        return [] unless @embedding_provider&.respond_to?(:embed)
        query_embedding = @embedding_provider.embed(query_text)
        search(query_embedding, top_k: top_k, user_id: user_id)
      end
    end
  end
end
