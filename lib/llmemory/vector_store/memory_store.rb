# frozen_string_literal: true

require_relative "base"

module Llmemory
  module VectorStore
    class MemoryStore < Base
      def initialize(embedding_provider: nil, cipher: nil)
        @entries = {}
        @embedding_provider = embedding_provider
        @cipher = cipher || Llmemory.build_cipher
      end

      def embed(text)
        return Array.new(1536, 0.0) unless @embedding_provider&.respond_to?(:embed)
        @embedding_provider.embed(text)
      end

      def last_usage
        return @embedding_provider.last_usage if @embedding_provider&.respond_to?(:last_usage)

        Llmemory::LLM::Usage.zero
      end

      def store(id:, embedding:, metadata: {}, user_id: nil)
        key = user_id ? "#{user_id}:#{id}" : id.to_s
        meta = (metadata || {}).dup
        if meta["text"] && @cipher.enabled?
          meta["text"] = @cipher.encrypt(meta["text"].to_s)
        elsif meta[:text] && @cipher.enabled?
          meta[:text] = @cipher.encrypt(meta[:text].to_s)
        end
        @entries[key] = {
          source_id: id.to_s,
          embedding: embedding.to_a.map(&:to_f),
          metadata: meta.merge("user_id" => user_id)
        }
        id
      end

      def search(query_embedding, top_k: 10, user_id: nil)
        query = query_embedding.to_a.map(&:to_f)
        return [] if query.empty?
        entries = user_id ? @entries.select { |k, _| k.to_s.start_with?("#{user_id}:") } : @entries
        scores = entries.map do |_key, data|
          sim = cosine_similarity(query, data[:embedding])
          { id: data[:source_id], score: sim, metadata: decrypt_metadata(data[:metadata]) }
        end
        scores.sort_by { |s| -s[:score] }.first(top_k)
      end

      def search_by_text(query_text, top_k: 10, user_id: nil)
        return [] unless @embedding_provider&.respond_to?(:embed)
        query_embedding = @embedding_provider.embed(query_text)
        search(query_embedding, top_k: top_k, user_id: user_id)
      end

      def delete(id:, user_id: nil)
        if user_id
          @entries.delete("#{user_id}:#{id}")
        else
          @entries.delete_if { |_key, data| data[:source_id].to_s == id.to_s }
        end
        true
      end

      private

      def decrypt_metadata(meta)
        return meta unless meta.is_a?(Hash) && @cipher.enabled?

        out = meta.dup
        text = out["text"] || out[:text]
        if text.is_a?(String) && @cipher.encrypted?(text)
          decrypted = @cipher.decrypt(text)
          out["text"] = decrypted
          out[:text] = decrypted
        end
        out
      end

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
