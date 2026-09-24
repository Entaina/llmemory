# frozen_string_literal: true

module Llmemory
  module Consolidation
    module TraceAttribution
      module_function

      def trace_ids_for_fact(fact_content, source_traces)
        traces = Array(source_traces).map do |t|
          id = t[:id] || t["id"]
          content = (t[:content] || t["content"]).to_s
          next if id.to_s.strip.empty?

          { id: id.to_s, content: content }
        end.compact
        return traces.map { |t| t[:id] } if traces.empty?

        fact_tokens = Llmemory::Tokenizer.content_tokens(fact_content.to_s).to_set
        return traces.map { |t| t[:id] } if fact_tokens.empty?

        scored = traces.map do |t|
          trace_tokens = Llmemory::Tokenizer.content_tokens(t[:content]).to_set
          overlap = (fact_tokens & trace_tokens).size
          [t[:id], overlap]
        end
        best = scored.max_by { |(_, o)| o }
        return traces.map { |t| t[:id] } if best.nil? || best[1].zero?

        max_overlap = best[1]
        scored.select { |(_, o)| o == max_overlap }.map(&:first)
      end

      def merge_trace_sources(provenance, trace_ids)
        base = provenance.is_a?(Hash) ? provenance.dup : {}
        sources = Array(base[:sources] || base["sources"]).dup
        Array(trace_ids).each do |tid|
          next if tid.to_s.strip.empty?

          entry = { type: "trace", id: tid.to_s }
          next if sources.any? { |s| (s[:type] || s["type"]).to_s == "trace" && (s[:id] || s["id"]).to_s == tid.to_s }

          sources << entry
        end
        base.merge(sources: sources)
      end
    end
  end
end
