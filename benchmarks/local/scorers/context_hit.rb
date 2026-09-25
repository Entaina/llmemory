# frozen_string_literal: true

require_relative "date_normalizer"

module LocalBenchmark
  module Scorers
    module ContextHit
      module_function

      def applicable?(conversation)
        conversation["workload_class"].to_s != "memsyco"
      end

      def hit?(context:, query:, turns: {})
        ctx = context.to_s
        return false if ctx.empty?

        refs = gold_references(query)
        return true if refs.any? { |gold| DateNormalizer.calendar_mentioned?(ctx, gold) }

        normalized_ctx = DateNormalizer.normalize_text(ctx)
        Array(query["gold_trace_ids"]).any? do |tid|
          content = DateNormalizer.normalize_text(turns[tid]&.dig("content"))
          !content.empty? && normalized_ctx.include?(content)
        end
      end

      def from_row(row, turns: {})
        conv = { "workload_class" => row[:workload_class] || row["workload_class"] }
        return nil unless applicable?(conv)

        query = {
          "gold_answer" => row[:gold_answer] || row["gold_answer"],
          "gold_answers" => row[:gold_answers] || row["gold_answers"],
          "gold_trace_ids" => row[:gold_trace_ids] || row["gold_trace_ids"]
        }
        hit?(context: row[:context] || row["context"], query: query, turns: turns)
      end

      def gold_references(query)
        alts = Array(query["gold_answers"] || query[:gold_answers]).map(&:to_s).reject(&:empty?)
        return alts unless alts.empty?

        gold = query["gold_answer"] || query[:gold_answer]
        gold.to_s.strip.empty? ? [] : [gold.to_s]
      end
    end
  end
end
