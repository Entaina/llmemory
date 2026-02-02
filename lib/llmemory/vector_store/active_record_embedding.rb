# frozen_string_literal: true

module Llmemory
  module VectorStore
    class ActiveRecordEmbedding < ::ActiveRecord::Base
      self.table_name = "llmemory_embeddings"
    end
  end
end
