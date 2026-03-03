# frozen_string_literal: true

module Llmemory
  module Retrieval
    class Bm25Scorer
      K1 = 1.5
      B = 0.75

      def initialize(k1: K1, b: B)
        @k1 = k1
        @b = b
      end

      def score_candidates(query, candidates)
        return [] if candidates.empty?

        query_tokens = tokenize(query)
        return candidates.map { |c| c.merge(bm25_score: 0.0, normalized_bm25: 0.0) } if query_tokens.empty?

        doc_tokens_list = candidates.map { |c| tokenize((c[:text] || c["text"]).to_s) }
        avg_doc_len = doc_tokens_list.map(&:size).sum.to_f / [doc_tokens_list.size, 1].max
        n_docs = candidates.size

        doc_freq = Hash.new(0)
        doc_tokens_list.each do |tokens|
          tokens.uniq.each { |t| doc_freq[t] += 1 }
        end

        candidates.each_with_index.map do |c, i|
          doc_tokens = doc_tokens_list[i]
          doc_len = doc_tokens.size
          bm25 = 0.0

          query_tokens.uniq.each do |term|
            tf = doc_tokens.count(term)
            next if tf.zero?

            n_qi = doc_freq[term]
            idf = Math.log((n_docs - n_qi + 0.5) / (n_qi + 0.5) + 1.0)
            numerator = tf * (@k1 + 1)
            denom = tf + @k1 * (1 - @b + @b * doc_len.to_f / [avg_doc_len, 1].max)
            bm25 += idf * numerator / denom
          end

          c.merge(bm25_score: bm25)
        end.tap do |scored|
          max_bm25 = scored.map { |s| s[:bm25_score] }.max.to_f
          max_bm25 = 1.0 if max_bm25.zero?
          scored.each { |s| s[:normalized_bm25] = s[:bm25_score] / max_bm25 }
        end
      end

      private

      def tokenize(text)
        text.to_s.downcase.scan(/\b[a-z0-9]{2,}\b/)
      end
    end
  end
end
