# frozen_string_literal: true

module Llmemory
  module ZeroMem
    class Router
      RELATIONAL_WORKLOADS = %i[multi_hop].freeze
      LOCAL_WORKLOADS = %i[temporal procedural cross_session local_fact].freeze

      def route(profile, hierarchy_scores:, graph_scores:, config: Llmemory.configuration)
        weights, route, tie_break = route_for_workload(profile, config)
        if tie_break
          weights = resolve_tie(weights, hierarchy_scores, graph_scores, profile)
        end

        {
          route: route,
          weights: weights,
          rho: weights[:graph],
          tie_break: tie_break
        }
      end

      private

      def route_for_workload(profile, config)
        workload = profile.workload_class
        if RELATIONAL_WORKLOADS.include?(workload) || profile.aggregation_cues.any?
          return [relational_weights(config), :relational, false]
        end
        if LOCAL_WORKLOADS.include?(workload)
          return [local_weights(config), :local, false]
        end
        if workload == :current_state
          base = profile.subject_entities.size >= 2 ? relational_weights(config) : local_weights(config)
          return [base, :current_state, profile.subject_entities.size < 2]
        end

        [local_weights(config), :local, true]
      end

      def relational_weights(config)
        rho = config.zero_mem_graph_weight || 0.6
        { graph: rho.to_f, hierarchy: 1.0 - rho.to_f }
      end

      def local_weights(_config)
        { graph: 0.4, hierarchy: 0.6 }
      end

      def resolve_tie(default_weights, hierarchy_scores, graph_scores, profile)
        h = anchor_confidence(hierarchy_scores, profile)
        g = anchor_confidence(graph_scores, profile)
        if g > h
          relational_weights(Llmemory.configuration)
        elsif h > g
          local_weights(Llmemory.configuration)
        else
          default_weights
        end
      end

      def anchor_confidence(scores, profile)
        return 0.0 if scores.nil? || scores.empty?

        scores.values.sum.to_f / scores.size
      end
    end
  end
end
