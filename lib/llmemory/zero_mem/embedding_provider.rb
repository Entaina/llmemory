# frozen_string_literal: true

module Llmemory
  module ZeroMem
    module EmbeddingProvider
      def embed(texts)
        raise NotImplementedError
      end

      def model
        raise NotImplementedError
      end

      def dimensions
        raise NotImplementedError
      end

      def local?
        false
      end

      def last_usage
        Llmemory::LLM::Usage.zero
      end

      def embed_one(text)
        embed([text]).first
      end
    end

    # Deterministic vectors for tests (no HTTP).
    class FakeEmbeddingProvider
      include EmbeddingProvider

      attr_reader :calls

      def initialize(dimensions: 8, model: "fake-embed")
        @dimensions = dimensions
        @model = model
        @calls = 0
      end

      def embed(texts)
        @calls += 1
        Array(texts).map { |text| vector_for(text) }
      end

      def model
        @model
      end

      def dimensions
        @dimensions
      end

      def local?
        true
      end

      private

      def vector_for(text)
        seed = Digest::SHA256.hexdigest(text.to_s)
        @dimensions.times.map do |i|
          byte = seed.bytes[i % seed.bytes.length] || 0
          (byte / 255.0)
        end
      end
    end
  end
end

require "digest"
