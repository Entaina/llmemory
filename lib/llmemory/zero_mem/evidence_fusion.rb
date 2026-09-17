# frozen_string_literal: true

module Llmemory
  module ZeroMem
    class EvidenceFusion
      # When all raw scores are equal, min-max yields this normalized value (see benchmarks/zero_mem/profile.yml).
      EQUAL_SCORE_NORMALIZED = 0.5

      def fuse(graph_scores:, hierarchy_scores:, weights:)
        g_norm = min_max(graph_scores)
        h_norm = min_max(hierarchy_scores)
        ids = (g_norm.keys + h_norm.keys).uniq

        fused = ids.map do |trace_id|
          graph = g_norm.fetch(trace_id, 0.0)
          hierarchy = h_norm.fetch(trace_id, 0.0)
          graph_w = weights.fetch(:graph, 0.5).to_f
          hierarchy_w = weights.fetch(:hierarchy, 0.5).to_f
          total = graph_w + hierarchy_w
          graph_w /= total
          hierarchy_w /= total
          final = (graph_w * graph) + (hierarchy_w * hierarchy)
          sources = []
          sources << :graph if graph_scores.key?(trace_id)
          sources << :hierarchy if hierarchy_scores.key?(trace_id)

          {
            trace_id: trace_id,
            graph: graph,
            hierarchy: hierarchy,
            graph_raw: graph_scores[trace_id],
            hierarchy_raw: hierarchy_scores[trace_id],
            final: final,
            sources: sources
          }
        end

        fused.sort_by { |row| [-row[:final], row[:trace_id]] }
      end

      def min_max(scores)
        return {} if scores.nil? || scores.empty?

        values = scores.values.map(&:to_f)
        min = values.min
        max = values.max
        if max == min
          return scores.keys.to_h { |id| [id, EQUAL_SCORE_NORMALIZED] }
        end

        scores.transform_values do |v|
          ((v.to_f - min) / (max - min)).clamp(0.0, 1.0)
        end
      end
    end
  end
end
