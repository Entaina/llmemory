# frozen_string_literal: true

module Llmemory
  module ZeroMem
    class EvidenceClosure
      DEFAULT_BRIDGE_BUDGET = 4
      DEFAULT_NEIGHBOR_BUDGET = 4

      def initialize(storage, config: Llmemory.configuration)
        @storage = storage
        @config = config
      end

      # Expands fused seeds with relational bridges and local neighbors inside the boundary.
      def expand(user_id:, profile:, seed_trace_ids:, fused_ranking:)
        seed_trace_ids = Array(seed_trace_ids).map(&:to_s).uniq
        return empty(seed_trace_ids) if seed_trace_ids.empty?

        bridge_budget = [seed_trace_ids.size, DEFAULT_BRIDGE_BUDGET].min
        neighbor_budget = DEFAULT_NEIGHBOR_BUDGET
        per_seed = [neighbor_budget / [seed_trace_ids.size, 1].max, 1].max

        closure_ids = []
        bridges = []
        groups = []

        seed_trace_ids.each do |seed_id|
          group = [seed_id]
          added = 0
          prev, nxt = @storage.adjacent_traces(user_id, seed_id)
          [prev, nxt].compact.each do |tid|
            break if added >= per_seed
            next if seed_trace_ids.include?(tid)
            next unless trace_ok?(user_id, tid, profile)

            closure_ids << tid
            bridges << [seed_id, tid]
            group << tid
            added += 1
          end
          groups << group if group.size > 1
        end

        span = @config.zero_mem_local_span.to_i
        span = 2 if span <= 0
        seed_trace_ids.each do |seed_id|
          trace = @storage.get_trace(user_id, seed_id)
          next unless trace

          session_traces = @storage.list_traces(user_id, session_id: trace.session_id)
          by_seq = session_traces.each_with_object({}) { |t, acc| acc[t.sequence] = t.id }
          ((trace.sequence - span)..(trace.sequence + span)).each do |seq|
            tid = by_seq[seq]
            next if tid.nil? || seed_trace_ids.include?(tid) || closure_ids.include?(tid)
            next unless trace_ok?(user_id, tid, profile)

            closure_ids << tid
          end
        end

        closure_ids = closure_ids.uniq.first(bridge_budget + neighbor_budget)
        {
          seed_trace_ids: seed_trace_ids,
          closure_trace_ids: closure_ids,
          bridges: bridges.first(bridge_budget),
          atomic_groups: groups.map { |g| g.uniq.sort }
        }
      end

      private

      def empty(seed_trace_ids)
        {
          seed_trace_ids: seed_trace_ids,
          closure_trace_ids: [],
          bridges: [],
          atomic_groups: []
        }
      end

      def trace_ok?(user_id, trace_id, profile)
        trace = @storage.get_trace(user_id, trace_id)
        return false unless trace&.active?

        boundary_match?(trace, profile.boundary)
      end

      def boundary_match?(trace, boundary)
        return true unless boundary

        ok = true
        ok &&= (trace.session_id == boundary[:session_id].to_s) if boundary[:session_id]
        ok &&= (trace.boundary_id == boundary[:boundary_id].to_s) if boundary[:boundary_id]
        ok
      end
    end
  end
end
