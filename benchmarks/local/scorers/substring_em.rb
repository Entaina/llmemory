# frozen_string_literal: true

module LocalBenchmark
  module Scorers
    module SubstringEM
      module_function

      def match?(prediction, reference)
        pred = normalize(prediction)
        ref = normalize(reference)
        return true if pred == ref
        return false if ref.empty?

        pred.include?(ref) || ref.include?(pred)
      end

      def score_row(row)
        gold = row[:gold_answer] || row.dig(:query, :gold_answer)
        return nil unless gold

        match?(row[:prediction] || row["prediction"], gold) ? 1.0 : 0.0
      end

      def normalize(text)
        text.to_s.downcase.strip.gsub(/\s+/, " ")
      end

      def aggregate(rows)
        scored = rows.filter_map { |r| score_row(r) }
        return { mean: nil, count: 0 } if scored.empty?

        { mean: scored.sum / scored.size, count: scored.size }
      end
    end
  end
end
