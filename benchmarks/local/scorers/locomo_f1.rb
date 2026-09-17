# frozen_string_literal: true

module LocalBenchmark
  module Scorers
    # LoCoMo task_eval/evaluation.py F1 (token overlap + Porter-style stem).
    module LoCoMoF1
      module_function

      ADVERSARIAL_MARKERS = [
        "no information available",
        "not mentioned",
        "i don't know",
        "don't know"
      ].freeze

      def score_row(row)
        category = row[:category] || row["category"]
        prediction = row[:prediction] || row["prediction"]
        gold_answer = row[:gold_answer] || row["gold_answer"]
        return nil if gold_answer.nil? || gold_answer.to_s.empty?

        locomo_f1(category: category, prediction: prediction, gold_answer: gold_answer)
      end

      def locomo_f1(category:, prediction:, gold_answer:)
        cat = category.to_i
        output = prediction.to_s
        answer = gold_answer.to_s
        answer = answer.split(";").first.strip if cat == 3

        case cat
        when 2, 3, 4
          f1_score(output, answer)
        when 1
          multi_answer_f1(output, answer)
        when 5
          adversarial_score(output)
        else
          f1_score(output, answer)
        end
      end

      def adversarial_score(output)
        down = output.downcase
        ADVERSARIAL_MARKERS.any? { |m| down.include?(m) } ? 1.0 : 0.0
      end

      def multi_answer_f1(prediction, ground_truth)
        predictions = prediction.split(",").map(&:strip)
        ground_truths = ground_truth.split(",").map(&:strip)
        scores = ground_truths.map do |gt|
          predictions.map { |pred| f1_score(pred, gt) }.max || 0.0
        end
        return 0.0 if scores.empty?

        scores.sum / scores.size
      end

      def f1_score(prediction, ground_truth)
        prediction_tokens = normalize_answer(prediction).split.map { |w| stem(w) }
        ground_truth_tokens = normalize_answer(ground_truth).split.map { |w| stem(w) }
        return 0.0 if prediction_tokens.empty? || ground_truth_tokens.empty?

        pred_counts = count_tokens(prediction_tokens)
        ref_counts = count_tokens(ground_truth_tokens)
        common = pred_counts.keys & ref_counts.keys
        num_same = common.sum { |t| [pred_counts[t], ref_counts[t]].min }
        return 0.0 if num_same.zero?

        precision = num_same.to_f / prediction_tokens.size
        recall = num_same.to_f / ground_truth_tokens.size
        (2 * precision * recall) / (precision + recall)
      end

      def count_tokens(tokens)
        tokens.each_with_object(Hash.new(0)) { |t, h| h[t] += 1 }
      end

      def normalize_answer(text)
        s = text.to_s.gsub(",", "")
        s = s.gsub(/\b(a|an|the|and)\b/i, " ")
        s.downcase.strip.gsub(/\s+/, " ")
      end

      def stem(word)
        w = word.to_s.downcase
        return w if w.length <= 3

        w = w.sub(/(ies|ied)$/, "i")
        w = w.sub(/(ing|ed|es|s)$/, "")
        w
      end

      def aggregate(rows)
        scored = rows.filter_map do |row|
          s = score_row(row)
          next if s.nil?

          { category: row[:category] || row["category"], locomo_f1: s }
        end
        return { mean: nil, by_category: {}, count: 0 } if scored.empty?

        by_cat = scored.group_by { |r| r[:category] }
        {
          count: scored.size,
          mean: scored.sum { |r| r[:locomo_f1] } / scored.size,
          by_category: by_cat.transform_values do |vals|
            { mean: vals.sum { |v| v[:locomo_f1] } / vals.size, count: vals.size }
          end
        }
      end
    end
  end
end
