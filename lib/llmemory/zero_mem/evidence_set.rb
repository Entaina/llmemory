# frozen_string_literal: true

require_relative "../temporal/snippet_enricher"

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

        items = evidence.dup
        items.sort_by! { |ev| ev.occurred_at.to_f } if temporal_intent?
        normalize_confidence!(items)

        lines = ["=== ZERO-MEM EVIDENCE ===", ""]
        if items.any?
          top = items.max_by(&:score)
          lines << "Most relevant: #{top.trace_id} (conf=#{format('%.2f', top.confidence)})"
          lines << ""
        end

        day_counts = evidence_day_counts(items)
        items.each do |ev|
          ts_label = format_evidence_time(ev, day_counts: day_counts)
          body = snippet(enriched_content(ev))
          lines << "[#{ev.trace_id}] #{ts_label} #{ev.session_id} #{ev.role} (conf=#{format('%.2f', ev.confidence)}): #{body}"
        end

        if temporal_intent? && items.size > 1
          lines << ""
          lines << "Timeline:"
          dated = items.reject(&:occurred_at_inferred).filter_map do |ev|
            time = ev.occurred_at.is_a?(Time) ? ev.occurred_at : Llmemory.parse_occurred_at(ev.occurred_at)
            next unless time

            { time: time, text: enriched_content(ev), trace_id: ev.trace_id }
          end
          Temporal::SnippetEnricher.timeline_deltas(dated).each { |line| lines << line }
        end

        lines << ""
        lines << "=== END ZERO-MEM EVIDENCE ==="
        lines.join("\n")
      end

      private

      def temporal_intent?
        return false unless profile

        workload = profile.workload_class || profile[:workload_class]
        freshness = profile.freshness_requirement
        freshness = profile[:freshness_requirement] if freshness.nil? && profile.is_a?(Hash)
        answer = profile.answer_type || profile[:answer_type]
        workload == :temporal || freshness == true || answer == :datetime
      end

      def evidence_day_counts(items)
        items.each_with_object(Hash.new(0)) do |ev, acc|
          next if ev.occurred_at_inferred

          time = ev.occurred_at.is_a?(Time) ? ev.occurred_at : Llmemory.parse_occurred_at(ev.occurred_at)
          next unless time

          acc[time.utc.to_date] += 1
        end
      end

      def enriched_content(ev)
        Temporal::SnippetEnricher.enrich(
          ev.content,
          reference_time: ev.occurred_at,
          occurred_at_inferred: ev.occurred_at_inferred
        )
      end

      def format_evidence_time(ev, day_counts: nil)
        return "(undated)" if ev.occurred_at_inferred

        time = ev.occurred_at.is_a?(Time) ? ev.occurred_at : Llmemory.parse_occurred_at(ev.occurred_at)
        return ev.occurred_at.to_s unless time

        label = time.utc.strftime("%a %-d %b %Y")
        if day_counts && day_counts[time.utc.to_date].to_i > 1
          label = "#{label} #{time.utc.strftime('%H:%M')}"
        end
        label
      end

      def normalize_confidence!(items)
        scores = items.map(&:score)
        min, max = scores.minmax
        span = max - min
        return if span < 1e-6

        items.each do |ev|
          normalized = 0.08 + 0.92 * ((ev.score - min) / span)
          ev.instance_variable_set(:@confidence, normalized)
          ev.instance_variable_set(:@score, normalized)
        end
      end

      def snippet(text, limit = nil)
        limit ||= Llmemory.configuration.zero_mem_snippet_chars.to_i
        limit = 600 if limit <= 0
        str = text.to_s
        return str if str.length <= limit

        terms = Array(profile&.keywords).map(&:downcase).select { |t| t.length >= 3 }
        down = str.downcase
        anchor = terms.find { |t| down.include?(t) }
        if anchor
          idx = down.index(anchor)
          start = [idx - (limit / 3), 0].max
          excerpt = str[start, limit]
          prefix = start.positive? ? "..." : ""
          suffix = (start + limit) < str.length ? "..." : ""
          return "#{prefix}#{excerpt}#{suffix}"
        end

        "#{str[0, limit]}..."
      end
    end
  end
end
