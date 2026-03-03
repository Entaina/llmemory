# frozen_string_literal: true

require_relative "temporal_ranker"
require_relative "context_assembler"
require_relative "bm25_scorer"
require_relative "mmr_reranker"

module Llmemory
  module Retrieval
    class Engine
      RELEVANCE_THRESHOLD = 0.7

      def initialize(memory, llm: nil)
        @memory = memory
        @llm = llm || Llmemory::LLM.client
        @ranker = TemporalRanker.new
        @assembler = ContextAssembler.new
        @bm25_scorer = Bm25Scorer.new
        @mmr_reranker = MmrReranker.new(lambda: Llmemory.configuration.mmr_lambda)
      end

      def retrieve_for_inference(user_message, user_id: nil, max_tokens: nil)
        user_id ||= @memory.respond_to?(:user_id) ? @memory.user_id : nil
        search_query = generate_query(user_message)
        candidates = fetch_candidates(search_query, user_id)
        candidates = apply_hybrid_scoring(candidates, search_query) if Llmemory.configuration.hybrid_search_enabled

        relevant = filter_by_relevance(candidates, user_message)
        ranked = @ranker.rank(relevant)
        ranked = @mmr_reranker.rerank(ranked) if Llmemory.configuration.mmr_enabled
        @assembler.assemble(ranked, max_tokens: max_tokens)
      end

      private

      def generate_query(user_message)
        return user_message.to_s if user_message.to_s.length <= 100
        prompt = <<~PROMPT
          Summarize this user message into a short search query (one sentence, under 15 words) to find relevant memories.
          Message: #{user_message}
          Return only the search query.
        PROMPT
        @llm.invoke(prompt.strip).to_s.strip
      rescue Llmemory::LLMError
        user_message.to_s[0..200]
      end

      def fetch_candidates(search_query, user_id)
        return [] unless @memory.respond_to?(:search_candidates)

        raw = @memory.search_candidates(search_query, user_id: user_id, top_k: 20)
        raw.map do |c|
          {
            text: c[:text] || c["text"],
            timestamp: parse_timestamp(c[:timestamp] || c["timestamp"] || c[:created_at] || c["created_at"]),
            score: (c[:score] || c["score"] || 1.0).to_f
          }
        end
      end

      def parse_timestamp(ts)
        return ts if ts.is_a?(Time)
        return Time.parse(ts.to_s) if ts
        Time.now
      end

      def apply_hybrid_scoring(candidates, query)
        return candidates if candidates.empty?

        scored = @bm25_scorer.score_candidates(query, candidates)
        weight = Llmemory.configuration.bm25_weight.to_f
        weight = 0.3 if weight < 0 || weight > 1

        scored.map do |c|
          vector_score = (c[:score] || c["score"] || 1.0).to_f
          bm25_norm = (c[:normalized_bm25] || 0).to_f
          hybrid = weight * bm25_norm + (1 - weight) * vector_score
          c.merge(score: hybrid)
        end
      end

      def filter_by_relevance(candidates, user_message)
        return candidates if candidates.size <= 5
        user_lower = user_message.to_s.downcase
        candidates.select do |c|
          text = (c[:text] || c["text"]).to_s.downcase
          score = (c[:score] || c["score"] || 1.0).to_f
          next true if score >= RELEVANCE_THRESHOLD
          next true if user_lower.split.any? { |w| w.length > 3 && text.include?(w) }
          score >= 0.5
        end
      end
    end
  end
end
