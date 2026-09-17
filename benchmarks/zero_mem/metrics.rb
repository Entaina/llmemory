# frozen_string_literal: true

module ZeroMemBenchmark
  module Metrics
    module_function

    def recall_at_k(ranked_ids, gold_ids, k)
      gold = Array(gold_ids).map(&:to_s).uniq
      return 0.0 if gold.empty?

      top = ranked_ids.first(k).map(&:to_s)
      hits = gold.count { |id| top.include?(id) }
      hits.to_f / gold.size
    end

    def recall_at(ks, ranked_ids, gold_ids)
      ks.to_h { |k| [:"recall@#{k}", recall_at_k(ranked_ids, gold_ids, k)] }
    end

    def mrr(ranked_ids, gold_ids)
      gold = Array(gold_ids).map(&:to_s).uniq
      return 0.0 if gold.empty?

      ranked_ids.each_with_index do |id, idx|
        return 1.0 / (idx + 1) if gold.include?(id.to_s)
      end
      0.0
    end

    def ndcg_at_k(ranked_ids, gold_ids, k)
      gold = Array(gold_ids).map(&:to_s).uniq
      return 0.0 if gold.empty?

      top = ranked_ids.first(k).map(&:to_s)
      dcg = top.each_with_index.sum do |id, idx|
        gold.include?(id) ? 1.0 / Math.log2(idx + 2) : 0.0
      end
      ideal_hits = [gold.size, k].min
      idcg = (0...ideal_hits).sum { |idx| 1.0 / Math.log2(idx + 2) }
      return 0.0 if idcg.zero?

      dcg / idcg
    end

    def token_f1(prediction, reference)
      pred_tokens = normalize_tokens(prediction)
      ref_tokens = normalize_tokens(reference)
      return 0.0 if pred_tokens.empty? || ref_tokens.empty?

      common = (pred_tokens & ref_tokens).size
      precision = common.to_f / pred_tokens.size
      recall = common.to_f / ref_tokens.size
      return 0.0 if (precision + recall).zero?

      2 * precision * recall / (precision + recall)
    end

    def bleu1(prediction, reference)
      pred = normalize_tokens(prediction)
      ref = normalize_tokens(reference)
      return 0.0 if pred.empty? || ref.empty?

      hits = pred.count { |t| ref.include?(t) }
      hits.to_f / pred.size
    end

    def rouge_l(prediction, reference)
      pred = normalize_tokens(prediction)
      ref = normalize_tokens(reference)
      return 0.0 if pred.empty? || ref.empty?

      lcs = longest_common_subsequence_length(pred, ref)
      return 0.0 if lcs.zero?

      prec = lcs.to_f / pred.size
      rec = lcs.to_f / ref.size
      2 * prec * rec / (prec + rec)
    end

    def exact_match(prediction, reference)
      normalize_text(prediction) == normalize_text(reference) ? 1.0 : 0.0
    end

    def normalize_text(text)
      text.to_s.downcase.strip.gsub(/\s+/, " ")
    end

    def normalize_tokens(text)
      normalize_text(text).split(/\W+/).reject(&:empty?)
    end

    def longest_common_subsequence_length(a, b)
      rows = a.size
      cols = b.size
      prev = Array.new(cols + 1, 0)
      cur = Array.new(cols + 1, 0)

      (1..rows).each do |i|
        (1..cols).each do |j|
          cur[j] = if a[i - 1] == b[j - 1]
                     prev[j - 1] + 1
                   else
                     [prev[j], cur[j - 1]].max
                   end
        end
        prev, cur = cur, Array.new(cols + 1, 0)
      end
      prev[cols]
    end
  end
end
