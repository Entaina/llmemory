# frozen_string_literal: true

require "json"

module LocalBenchmark
  module Scorers
    module ArenaMatch
      module_function

      def score(prediction, gold_answer)
        gold = parse_gold(gold_answer)
        return 0.0 unless gold

        pred = prediction.to_s.downcase
        asin = gold["target_asin"].to_s.downcase
        return 0.0 if asin.empty? || !pred.include?(asin)

        attrs = Array(gold["attributes"])
        return 1.0 if attrs.empty?

        hits = attrs.count { |a| pred.include?(a.to_s.downcase) }
        hits.to_f / attrs.size
      end

      def aggregate(rows)
        scored = rows.filter_map do |row|
          next if row[:gold_answer].to_s.strip.empty?

          score(row[:prediction], row[:gold_answer])
        end
        return { mean: nil, count: 0 } if scored.empty?

        { mean: scored.sum / scored.size, count: scored.size }
      end

      def parse_gold(raw)
        return raw if raw.is_a?(Hash)

        text = raw.to_s.strip
        return nil if text.empty?

        if text.start_with?("{")
          JSON.parse(text)
        else
          nil
        end
      rescue JSON::ParserError
        nil
      end
    end
  end
end
