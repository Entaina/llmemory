# frozen_string_literal: true

require "set"

require_relative "hybrid_result"
require_relative "context_assembler"

module Llmemory
  module Retrieval
    class HybridFusion
      RRF_K = 60.0
      CLOSURE_DISCOUNT = 0.04

      def initialize(assembler: nil)
        @assembler = assembler || ContextAssembler.new
      end

      def fuse(classic_candidates:, evidence_set:, max_tokens: nil, skip_resources: true)
        profile = evidence_set&.profile
        facts = classic_rows(classic_candidates, skip_resources: skip_resources)
        traces = trace_rows(evidence_set)
        seed_ids = traces.select { |t| t[:seed] }.map { |t| t[:trace_id].to_s }.to_set

        scored = rrf_merge(facts, traces, profile: profile)
        scored = dedupe_text_rows(scored)
        scored = apply_corroboration(scored, seed_ids, profile: profile)
        ordered = drop_redundant_traces(scored, profile: profile)
        ordered = limit_uncorroborated_traces(ordered, profile: profile)
        packed = pack_items(ordered, max_tokens: max_tokens)

        corroborated = packed.count { |i| i[:via_trace_id] }
        HybridResult.new(
          items: packed,
          profile: profile,
          metrics: {
            fact_count: packed.count { |i| i[:kind] == :fact },
            trace_count: packed.count { |i| i[:kind] == :trace },
            summary_count: packed.count { |i| i[:kind] == :summary },
            corroborated_count: corroborated
          }
        )
      end

      private

      def classic_rows(candidates, skip_resources:)
        Array(candidates).filter_map do |c|
          kind = (c[:kind] || c["kind"] || :fact).to_sym
          next if skip_resources && kind == :resource

          prov = c[:provenance] || c["provenance"]
          {
            key: "fact:#{c[:id] || c[:text].to_s[0, 40]}",
            kind: kind == :summary || kind == :daily_log ? kind : :fact,
            id: c[:id],
            text: c[:text] || c["text"],
            score: (c[:temporal_score] || c[:score] || 0).to_f,
            timestamp: c[:timestamp],
            event_date: c[:event_date] || c["event_date"],
            provenance: prov,
            trace_source_ids: trace_ids_from_provenance(prov),
            seed: false,
            closure: false
          }
        end
      end

      def trace_rows(evidence_set)
        return [] unless evidence_set

        evidence_set.evidence.map do |ev|
          {
            key: "trace:#{ev.trace_id}",
            kind: :trace,
            trace_id: ev.trace_id,
            text: ev.content,
            score: ev.score.to_f,
            occurred_at: ev.occurred_at,
            occurred_at_inferred: ev.occurred_at_inferred,
            seed: ev.seed,
            closure: ev.closure && !ev.seed,
            provenance: nil,
            trace_source_ids: []
          }
        end
      end

      DATE_IN_TEXT = /\b(\d{4}-\d{2}-\d{2}|january|february|march|april|may|june|july|august|september|october|november|december)\b/i

      def rrf_merge(facts, traces, profile:)
        fact_ranks = facts.each_with_index.to_h { |f, i| [f[:key], i + 1] }
        trace_ranks = traces.each_with_index.to_h { |t, i| [t[:key], i + 1] }
        keys = (facts.map { |f| f[:key] } + traces.map { |t| t[:key] }).uniq
        rows = keys.map { |key| facts.find { |f| f[:key] == key } || traces.find { |t| t[:key] == key } }
        df = token_document_frequency(rows, profile)

        rows.map do |row|
          fr = fact_ranks[row[:key]]
          tr = trace_ranks[row[:key]]
          rrf = 0.0
          rrf += 1.0 / (RRF_K + fr) if fr
          rrf += 1.0 / (RRF_K + tr) if tr
          rrf += workload_prior(row, profile)
          rrf += lexical_prior(row, profile, df)
          rrf += identity_prior(row, profile)
          rrf += person_prior(row, profile)
          row.merge(fusion_score: rrf)
        end.sort_by { |r| -r[:fusion_score] }
      end

      def token_document_frequency(rows, profile)
        tokens = query_tokens(profile)
        stemmed_rows = rows.map do |row|
          Llmemory::Tokenizer.tokenize(row[:text]).map { |token| Llmemory::Tokenizer.stem(token) }
        end
        tokens.to_h do |token|
          [token, stemmed_rows.count { |words| words.include?(token) }]
        end
      end

      def query_tokens(profile)
        Array(profile&.keywords).map { |t| Llmemory::Tokenizer.stem(t) }.select { |t| t.length >= 4 }.uniq
      end

      def lexical_prior(row, profile, df = {})
        tokens = query_tokens(profile)
        return 0.0 if tokens.empty?

        down = row[:text].to_s.downcase
        stemmed = Llmemory::Tokenizer.tokenize(row[:text]).map { |token| Llmemory::Tokenizer.stem(token) }
        hits = tokens.select { |token| stemmed.include?(token) || down.include?(token) }
        return -0.04 if hits.empty?

        score = hits.sum do |token|
          freq = df[token].to_i
          freq = 1 if freq < 1
          0.12 / Math.log(1.5 + freq)
        end
        rarest = tokens.min_by { |token| df[token].to_i.positive? ? df[token].to_i : 10_000 }
        if rarest && df[rarest].to_i.between?(1, 4) && !stemmed.include?(rarest) && !down.include?(rarest)
          score -= 0.12
        end
        score
      end

      def dedupe_text_rows(rows)
        seen = {}
        rows.filter_map do |row|
          key = row[:text].to_s.strip.downcase.gsub(/\s+/, " ")
          next row if key.empty?
          next if seen[key]

          seen[key] = true
          row
        end
      end

      def person_prior(row, profile)
        return 0.0 unless profile&.answer_type == :person

        entities = Array(profile.subject_entities).map { |name| name.to_s.downcase }.select { |name| name.length >= 3 }
        return 0.0 if entities.empty?

        text = row[:text].to_s.downcase
        return 0.16 if entities.any? { |name| text.include?(name) }

        -0.1
      end

      def identity_prior(row, profile)
        query = Array(profile&.keywords).join(" ")
        return 0.0 unless query.match?(/\bidentity\b/) || profile&.answer_type == :person

        text = row[:text].to_s
        return 0.14 if text.match?(/\bis an?\s+\w+/i)
        return -0.06 if text.match?(/\b(going|went|swimming|planning|values)\b/i)

        0.0
      end

      def workload_prior(row, profile)
        return 0.0 unless profile

        workload = (profile.workload_class || profile[:workload_class]).to_sym
        case workload
        when :temporal
          return 0.1 if row[:event_date] || row[:text].to_s.match?(DATE_IN_TEXT)
          return 0.02 if row[:kind] == :trace

          0.0
        when :current_state
          return 0.08 if row[:kind] == :fact

          0.0
        when :local_fact
          return 0.06 if row[:kind] == :fact

          0.0
        else
          0.0
        end
      end

      def apply_corroboration(scored, seed_ids, profile:)
        temporal = temporal_profile?(profile)
        scored.map do |row|
          next row unless row[:kind] == :fact

          overlap = Array(row[:trace_source_ids]).select { |tid| seed_ids.include?(tid.to_s) }
          next row if overlap.empty?

          row.merge(
            fusion_score: row[:fusion_score] + 0.12,
            corroborated: true,
            via_trace_id: overlap.first,
            drop_trace_ids: temporal ? [] : overlap.map(&:to_s)
          )
        end.sort_by { |r| -r[:fusion_score] }
      end

      def drop_redundant_traces(scored, profile:)
        drop = Set.new
        unless temporal_profile?(profile)
          facts = scored.select { |row| row[:kind] == :fact && row[:corroborated] }
          scored.each do |row|
            next unless row[:kind] == :trace

            covering = facts.select { |fact| Array(fact[:drop_trace_ids]).include?(row[:trace_id].to_s) }
            next if covering.empty?
            next if covering.any? { |fact| omits_trace_name?(fact[:text], row[:text]) }

            drop << row[:trace_id].to_s
          end
        end

        scored.filter_map do |row|
          if row[:kind] == :trace && drop.include?(row[:trace_id].to_s)
            next
          end

          finalize_row(row, discount: row[:closure] ? CLOSURE_DISCOUNT : 0.0)
        end
      end

      def finalize_row(row, discount: 0.0)
        score = [row[:fusion_score].to_f - discount, 0.01].max
        {
          kind: row[:kind],
          id: row[:id],
          trace_id: row[:trace_id],
          text: row[:text],
          score: score,
          timestamp: row[:timestamp],
          event_date: row[:event_date],
          occurred_at: row[:occurred_at],
          occurred_at_inferred: row[:occurred_at_inferred] == true,
          trace_source_ids: row[:trace_source_ids],
          via_trace_id: row[:via_trace_id],
          seed: row[:seed],
          closure: row[:closure]
        }
      end

      def limit_uncorroborated_traces(ordered, profile:)
        return ordered unless current_state_profile?(profile)

        corroborated_trace_ids = ordered.filter_map do |row|
          next unless row[:kind] == :fact

          row[:via_trace_id]
        end.to_set
        newest_id = newest_seed_trace_id(ordered)
        covered_id = seed_covering_facts(ordered, profile)

        kept_seeds = 0
        ordered.select do |row|
          next true unless row[:kind] == :trace

          tid = row[:trace_id].to_s
          next false if row[:occurred_at_inferred] && !row[:seed]
          next true if newest_id && tid == newest_id
          next true if covered_id && tid == covered_id

          if corroborated_trace_ids.include?(tid)
            true
          elsif row[:seed]
            kept_seeds += 1
            kept_seeds <= (newest_id ? 1 : 2)
          else
            false
          end
        end
      end

      def seed_covering_facts(ordered, profile)
        facts = ordered.select { |row| row[:kind] == :fact }.map { |row| row[:text].to_s.downcase }.join("\n")
        tokens = Array(profile&.keywords).map(&:to_s).select { |token| token.length >= 4 }
        return nil if tokens.empty?

        seeds = ordered.select { |row| row[:kind] == :trace && row[:seed] }
        best = seeds.max_by do |row|
          text = row[:text].to_s.downcase
          uncovered = tokens.count { |token| text.include?(token) && !facts.include?(token) }
          [uncovered, row[:score].to_f]
        end
        return nil unless best

        text = best[:text].to_s.downcase
        uncovered = tokens.count { |token| text.include?(token) && !facts.include?(token) }
        uncovered.positive? ? best[:trace_id].to_s : nil
      end

      def newest_seed_trace_id(ordered)
        candidates = ordered.select do |row|
          row[:kind] == :trace && row[:seed] && row[:occurred_at] && row[:occurred_at_inferred] != true
        end
        candidates.max_by { |row| row[:occurred_at] }&.dig(:trace_id)&.to_s
      end

      def omits_trace_name?(fact_text, trace_text)
        names = trace_text.to_s.scan(/\b[A-Z][a-z]{2,}\b/).uniq
        names.any? { |name| !fact_text.to_s.include?(name) }
      end

      def current_state_profile?(profile)
        return false unless profile

        (profile.workload_class || profile[:workload_class]).to_sym == :current_state
      end

      def pack_items(ordered, max_tokens:)
        max_tokens ||= Llmemory.configuration.max_retrieval_tokens
        fact_ceiling_ratio = Llmemory.configuration.hybrid_classic_token_ratio.to_f
        fact_ceiling_ratio = 0.5 unless fact_ceiling_ratio.positive? && fact_ceiling_ratio < 1.0
        fact_token_ceiling = (max_tokens * fact_ceiling_ratio).to_i

        selected = []
        token_count = 0
        fact_tokens = 0

        ordered.each do |item|
          item_tokens = @assembler.count_tokens(item[:text].to_s)
          is_fact_like = %i[fact summary daily_log].include?(item[:kind])
          if token_count + item_tokens > max_tokens
            next
          end
          if is_fact_like && fact_tokens + item_tokens > fact_token_ceiling
            next
          end

          selected << item
          token_count += item_tokens
          fact_tokens += item_tokens if is_fact_like
        end

        selected
      end

      def trace_ids_from_provenance(prov)
        return [] unless prov.is_a?(Hash)

        Array(prov[:sources] || prov["sources"]).filter_map do |s|
          type = (s[:type] || s["type"]).to_s
          next unless type == "trace"

          (s[:id] || s["id"]).to_s
        end
      end

      def temporal_profile?(profile)
        return false unless profile

        workload = profile.workload_class || profile[:workload_class]
        answer = profile.answer_type || profile[:answer_type]
        workload == :temporal || answer == :datetime
      end
    end
  end
end
