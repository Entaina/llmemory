# frozen_string_literal: true

module Llmemory
  module Retrieval
    # Combines semantic, episodic and procedural memory for unified retrieval.
    class MultiSource
      def initialize(primary:, memory:)
        @primary = primary
        @memory = memory
      end

      def user_id
        @memory.user_id
      end

      def search_candidates(query, user_id: nil, top_k: 20)
        uid = user_id || @memory.user_id
        combined = []
        combined.concat(@primary.search_candidates(query, user_id: uid, top_k: top_k))
        combined.concat(@memory.episodic.search_candidates(query, user_id: uid, top_k: top_k))
        combined.concat(@memory.procedural.search_candidates(query, user_id: uid, top_k: top_k))
        combined
      end
    end
  end
end
