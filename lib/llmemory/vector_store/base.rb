# frozen_string_literal: true

module Llmemory
  module VectorStore
    class Base
      def embed(text)
        raise NotImplementedError, "#{self.class}#embed must be implemented"
      end

      def store(id:, embedding:, metadata: {})
        raise NotImplementedError, "#{self.class}#store must be implemented"
      end

      def search(query_embedding, top_k: 10)
        raise NotImplementedError, "#{self.class}#search must be implemented"
      end

      def delete(id:, user_id: nil)
        raise NotImplementedError, "#{self.class}#delete must be implemented"
      end
    end
  end
end
