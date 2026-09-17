# frozen_string_literal: true

module Llmemory
  module ZeroMem
    class EvidenceSet
      attr_reader :route, :profile, :evidence, :metrics, :explain, :degraded,
                  :relational_trace_scores, :hierarchy_traces, :relational_traces, :warnings,
                  :seed_evidence, :closure_evidence

      def initialize(route:, profile:, evidence:, metrics:, explain: nil, degraded: [],
                     relational_trace_scores: {}, hierarchy_traces: [], relational_traces: [],
                     warnings: [], seed_evidence: [], closure_evidence: [])
        @route = route
        @profile = profile
        @evidence = evidence
        @metrics = metrics
        @explain = explain
        @degraded = Array(degraded)
        @relational_trace_scores = relational_trace_scores
        @hierarchy_traces = hierarchy_traces
        @relational_traces = relational_traces
        @warnings = Array(warnings)
        @seed_evidence = Array(seed_evidence)
        @closure_evidence = Array(closure_evidence)
      end

      def recall_at_k(gold_trace_ids, k: nil)
        k ||= evidence.size
        gold = Array(gold_trace_ids).map(&:to_s)
        ranked = evidence.map(&:trace_id).first(k)
        hit = (gold & ranked).size
        {
          hit: hit,
          gold: gold.size,
          recall: gold.empty? ? 0.0 : hit.to_f / gold.size,
          ranked: ranked
        }
      end

      def to_context
        return "" if evidence.empty?

        lines = ["=== ZERO-MEM EVIDENCE ===", ""]
        evidence.each do |ev|
          ts = ev.occurred_at.is_a?(Time) ? ev.occurred_at.utc.iso8601 : ev.occurred_at.to_s
          lines << "[#{ev.trace_id}] #{ts} #{ev.session_id} #{ev.role}: #{ev.content}"
        end
        lines << ""
        lines << "=== END ZERO-MEM EVIDENCE ==="
        lines.join("\n")
      end
    end
  end
end
