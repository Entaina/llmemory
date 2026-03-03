# frozen_string_literal: true

module Llmemory
  module Retrieval
    class MmrReranker
      def initialize(lambda: 0.7)
        @lambda = lambda
      end

      def rerank(candidates, score_key: :temporal_score)
        return candidates if candidates.size <= 1

        selected = []
        remaining = candidates.dup

        while remaining.any?
          best_idx = nil
          best_mmr = -Float::INFINITY

          remaining.each_with_index do |cand, i|
            rel = (cand[score_key] || cand[score_key.to_s] || cand[:score] || cand["score"] || 0).to_f
            max_sim = selected.map { |s| similarity(cand, s) }.max || 0
            mmr = @lambda * rel - (1 - @lambda) * max_sim

            if mmr > best_mmr
              best_mmr = mmr
              best_idx = i
            end
          end

          break unless best_idx

          selected << remaining.delete_at(best_idx)
        end

        selected
      end

      private

      def similarity(a, b)
        text_a = tokenize((a[:text] || a["text"]).to_s)
        text_b = tokenize((b[:text] || b["text"]).to_s)
        return 0.0 if text_a.empty? || text_b.empty?

        intersection = (text_a & text_b).size
        union = (text_a | text_b).size
        union.zero? ? 0.0 : intersection.to_f / union
      end

      def tokenize(text)
        text.downcase.scan(/\b[a-z0-9]{2,}\b/).uniq
      end
    end
  end
end
