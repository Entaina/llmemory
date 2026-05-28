# frozen_string_literal: true

require_relative "vector_store/base"
require_relative "vector_store/openai_embeddings"
require_relative "vector_store/memory_store"

module Llmemory
  module VectorStore
    # Builds a vector store wired to OpenAI embeddings, selecting the backend
    # from config (:active_record persists in llmemory_embeddings; otherwise
    # in-process). `source_type` namespaces persisted embeddings so different
    # memory types (edges, episodes, skills) never collide in the shared table.
    def self.build(source_type: "edge")
      embeddings = OpenAIEmbeddings.new
      store_type = (Llmemory.configuration.long_term_store || :memory).to_s.to_sym
      if store_type == :active_record || store_type == :activerecord
        require_relative "vector_store/active_record_store"
        ActiveRecordStore.new(embedding_provider: embeddings, source_type: source_type)
      else
        MemoryStore.new(embedding_provider: embeddings)
      end
    end
  end
end
