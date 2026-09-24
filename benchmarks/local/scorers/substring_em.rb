# frozen_string_literal: true

require_relative "date_normalizer"

module LocalBenchmark
  module Scorers
    module SubstringEM
      module_function

      def match?(prediction, reference)
        pred = normalize(prediction)
        ref = normalize(reference)
        return true if pred == ref
        return false if ref.empty?

        return true if DateNormalizer.numeric_days_match?(prediction, reference)

        pred.include?(ref) || ref.include?(pred)
      end

      def score_row(row)
        refs = gold_references(row)
        return nil if refs.empty?

        pred = row[:prediction] || row["prediction"]
        refs.any? { |ref| match?(pred, ref) } ? 1.0 : 0.0
      end

      def gold_references(row)
        alts = row[:gold_answers] || row["gold_answers"]
        if alts.is_a?(Array) && !alts.empty?
          return alts.map(&:to_s).reject(&:empty?)
        end

        gold = row[:gold_answer] || row.dig(:query, :gold_answer)
        gold.to_s.strip.empty? ? [] : [gold.to_s]
      end

      def normalize(text)
        DateNormalizer.normalize_text(text).downcase.strip.gsub(/\s+/, " ")
      end

      def aggregate(rows)
        scored = rows.filter_map { |r| score_row(r) }
        return { mean: nil, count: 0 } if scored.empty?

        { mean: scored.sum / scored.size, count: scored.size }
      end
    end
  end
end
