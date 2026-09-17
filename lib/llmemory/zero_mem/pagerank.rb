# frozen_string_literal: true

module Llmemory
  module ZeroMem
    class PageRank
      def initialize(gamma: 0.6, max_iterations: 30, tolerance: 1e-6)
        @gamma = gamma.to_f
        @max_iterations = max_iterations
        @tolerance = tolerance
      end

      # graph: { node_id => [neighbor_ids] }, reset: { node_id => weight }
      def run(graph, reset)
        nodes = (graph.keys + reset.keys).uniq
        return {} if nodes.empty?

        out_degree = graph.transform_values { |nbs| [nbs.size, 1].max }
        rank = nodes.to_h { |n| [n, 1.0 / nodes.size] }
        reset_total = reset.values.sum
        reset = reset.transform_values { |w| reset_total.zero? ? 0.0 : w / reset_total }

        @max_iterations.times do
          next_rank = nodes.to_h { |n| [n, 0.0] }
          graph.each do |node, neighbors|
            share = rank[node] / out_degree[node]
            neighbors.each do |nb|
              next_rank[nb] ||= 0.0
              next_rank[nb] += @gamma * share
            end
          end
          nodes.each do |n|
            next_rank[n] += (1.0 - @gamma) * reset.fetch(n, 0.0)
          end
          delta = nodes.sum { |n| (next_rank[n] - rank[n]).abs }
          rank = next_rank
          break if delta < @tolerance
        end
        rank
      end
    end
  end
end
