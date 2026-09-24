# frozen_string_literal: true

require_relative "../temporal/snippet_enricher"

module Llmemory
  module Retrieval
    class HybridResult
      attr_reader :items, :profile, :metrics

      def initialize(items:, profile: nil, metrics: {})
        @items = Array(items)
        @profile = profile
        @metrics = metrics
      end

      def to_context
        return "" if items.empty?

        ordered = ordered_items_for_context
        normalize_scores!(ordered)

        lines = ["=== MEMORY ===", ""]
        top = ordered.max_by { |i| i[:score].to_f }
        if top && top[:score].to_f.positive?
          lines << "Most relevant (conf=#{format('%.2f', top[:score].to_f)}):"
          lines << ""
        end

        temporal = temporal_intent?
        timeline_items = temporal ? dated_timeline_items_from(ordered) : []

        ordered.each do |item|
          lines << format_item_line(item)
        end

        if temporal && timeline_items.size > 1
          lines << ""
          lines << "Timeline:"
          Temporal::SnippetEnricher.timeline_deltas(timeline_items).each { |line| lines << line }
        end

        if counting_intent? && timeline_items.size > 1
          lines << ""
          lines << "Event counts (by dated evidence):"
          timeline_items.group_by { |r| r[:text].to_s.downcase.strip[0, 80] }.each do |label, rows|
            lines << "- #{rows.size}× #{label}"
          end
        end

        lines << ""
        lines << "=== END MEMORY ==="
        lines.join("\n")
      end

      def ranked_trace_ids
        seen = {}
        items.each do |item|
          if item[:kind] == :trace && item[:trace_id]
            seen[item[:trace_id].to_s] = true
          end
          Array(item[:trace_source_ids]).each { |tid| seen[tid.to_s] = true }
        end
        ordered = []
        items.each do |item|
          if item[:kind] == :trace && item[:trace_id]
            tid = item[:trace_id].to_s
            ordered << tid unless ordered.include?(tid)
          end
          Array(item[:trace_source_ids]).each do |tid|
            tid = tid.to_s
            ordered << tid unless ordered.include?(tid)
          end
        end
        ordered
      end

      private

      def temporal_intent?
        return false unless profile

        workload = profile.workload_class || profile[:workload_class]
        answer = profile.answer_type || profile[:answer_type]
        freshness = profile.freshness_requirement
        freshness = profile[:freshness_requirement] if freshness.nil? && profile.is_a?(Hash)
        workload == :temporal || freshness == true || answer == :datetime
      end

      def format_item_line(item)
        ts = format_time(item)
        kind_label = item[:kind] == :fact ? "fact" : (item[:trace_id] || "turn")
        conf = format("%.2f", item[:score].to_f)
        via = item[:via_trace_id]
        suffix = via ? " via #{via}" : ""
        body = enriched_text(item)
        "[#{ts}] (#{kind_label}, conf=#{conf})#{suffix}: #{snippet(body)}"
      end

      def enriched_text(item)
        text = item[:text].to_s
        return text if item[:occurred_at_inferred]

        ref = item[:occurred_at] || item[:event_date] || item[:timestamp]
        Temporal::SnippetEnricher.enrich(text, reference_time: ref, occurred_at_inferred: false)
      end

      def ordered_items_for_context
        ranked = items.sort_by { |item| -item[:score].to_f }
        witness = witness_trace(ranked)
        return ranked unless witness

        lead, dissenting = ranked.partition { |item| !disagrees_with_witness?(item, witness) }
        quoting, rest = lead.partition { |item| quotes_witness?(item, witness) }
        quoting + rest + dissenting
      end

      def quotes_witness?(item, witness)
        return false unless item[:kind] == :fact || item[:kind] == :summary

        fact_dates = date_keys(item[:text])
        witness_dates = date_keys(witness[:text])
        return true if fact_dates.any? && witness_dates.any? && (fact_dates & witness_dates).any?

        fact_names = proper_names(item[:text])
        witness_names = proper_names(witness[:text])
        fact_names.any? && (fact_names & witness_names).any?
      end

      def witness_trace(ranked)
        traces = ranked.select { |item| item[:kind] == :trace }
        return nil if traces.empty?

        traces.max_by { |trace| [query_overlap(trace[:text]), trace[:score].to_f] }
      end

      def disagrees_with_witness?(item, witness)
        return false unless item[:kind] == :fact || item[:kind] == :summary

        fact_dates = date_keys(item[:text])
        witness_dates = date_keys(witness[:text])
        if fact_dates.any? && witness_dates.any?
          return (fact_dates & witness_dates).empty?
        end

        fact_names = proper_names(item[:text])
        witness_names = proper_names(witness[:text])
        return false if fact_names.empty? || (witness_names - fact_names).empty?

        query_overlap(witness[:text]) > query_overlap(item[:text])
      end

      def query_overlap(text)
        down = text.to_s.downcase
        query_tokens.count { |token| down.include?(token.downcase) }
      end

      def proper_names(text)
        text.to_s.scan(/\b[A-Z][a-z]{2,}\b/).uniq
      end

      def date_keys(text)
        keys = []
        source = text.to_s
        source.scan(/\b(\d{4})-(\d{2})-(\d{2})\b/) do |year, month, day|
          keys << "#{year}-#{month}-#{day}"
          keys << "#{month}-#{day}"
        end
        month_pattern = date_month_names.join("|")
        source.scan(/\b(#{month_pattern})\s+(\d{1,2})(?:st|nd|rd|th)?\b/i) do |name, day|
          keys << format("%02d-%02d", date_month_index(name), day.to_i)
        end
        source.scan(/\b(\d{1,2})(?:st|nd|rd|th)?\s+(#{month_pattern})\b/i) do |day, name|
          keys << format("%02d-%02d", date_month_index(name), day.to_i)
        end
        keys.uniq
      end

      def date_month_names
        %w[january february march april may june july august september october november december]
      end

      def date_month_index(name)
        date_month_names.index(name.downcase) + 1
      end

      def normalize_scores!(rows)
        scores = rows.map { |i| i[:score].to_f }
        min, max = scores.minmax
        span = max - min
        return rows if span < 1e-6

        rows.each { |i| i[:score] = 0.08 + 0.92 * ((i[:score].to_f - min) / span) }
      end

      def counting_intent?
        return true if profile&.answer_type == :number

        cues = profile&.aggregation_cues || profile&.[](:aggregation_cues)
        Array(cues).any?
      end

      def dated_timeline_items_from(rows)
        rows.filter_map do |i|
          next unless i[:kind] == :trace || i[:kind] == :fact
          next if i[:occurred_at_inferred]

          time = item_time(i)
          next unless time

          { time: time, text: enriched_text(i), trace_id: i[:trace_id] || i[:id] }
        end.sort_by { |r| r[:time] }
      end

      def dated_timeline_items
        dated_timeline_items_from(items)
      end

      def format_time(item)
        return "(undated)" if item[:occurred_at_inferred]

        time = item_time(item)
        return "(undated)" unless time

        time.utc.strftime("%a %-d %b %Y")
      end

      def item_time(item)
        raw = item[:occurred_at] || item[:event_date] || item[:timestamp]
        return raw if raw.is_a?(Time)
        return Llmemory.parse_occurred_at(raw) if raw

        nil
      end

      def snippet(text, limit = 600)
        str = text.to_s
        return str if str.length <= limit

        sentences = str.split(/(?<=[.!?])\s+/)
        q_tokens = query_tokens
        if sentences.size > 1 && q_tokens.any?
          covered = []
          picked = []
          pool = sentences.dup
          while pool.any?
            best = pool.max_by do |sentence|
              q_tokens.count { |token| sentence.downcase.include?(token.downcase) && !covered.include?(token) }
            end
            hits = q_tokens.select { |token| best.downcase.include?(token.downcase) && !covered.include?(token) }
            break if hits.empty?
            break if picked.any? && (picked.join(" ").length + best.length) > (limit - 240)

            picked << best
            covered |= hits
            pool.delete(best)
          end
          picked.sort_by! { |sentence| sentences.index(sentence) }
          append_named_sentence!(picked, sentences, limit)
          append_outcome_sentence!(picked, sentences, limit)
          return picked.join(" ") if picked.any?
        end

        "#{str[0, limit]}..."
      end

      def append_named_sentence!(picked, sentences, limit)
        picked_text = picked.join(" ")
        tokens = query_tokens.map(&:downcase)
        sentence = sentences
                   .reject { |candidate| picked.include?(candidate) }
                   .select do |candidate|
                     names = candidate.scan(/\b[A-Z][a-z]{2,}\b/).uniq
                     names.any? && names.any? { |name| !picked_text.include?(name) }
                   end
                   .max_by { |candidate| tokens.count { |token| candidate.downcase.include?(token) } }
        return unless sentence
        return if tokens.any? && tokens.none? { |token| sentence.downcase.include?(token) }

        while picked.any? && (picked.join(" ").length + sentence.length + 1) > limit
          picked.pop
        end
        picked << sentence if picked.empty? || (picked.join(" ").length + sentence.length + 1) <= limit
      end

      def append_outcome_sentence!(picked, sentences, limit)
        picked_text = picked.join(" ")
        names = picked_text.scan(/\b[A-Z][a-z]{2,}\b/).uniq
        return if names.empty?

        known = picked_text.downcase
        sentence = sentences
                   .reject { |candidate| picked.include?(candidate) }
                   .select { |candidate| names.any? { |name| candidate.include?(name) } }
                   .max_by { |candidate| novel_word_count(candidate, known) }
        return unless sentence
        return if novel_word_count(sentence, known) < 3

        while picked.any? && (picked.join(" ").length + sentence.length + 1) > limit
          picked.shift
        end
        picked << sentence if picked.empty? || (picked.join(" ").length + sentence.length + 1) <= limit
      end

      def novel_word_count(sentence, known)
        sentence.downcase.scan(/[a-z]{5,}/).count { |word| !known.include?(word) }
      end

      def query_tokens
        words = Array(profile&.keywords || profile&.[](:keywords))
        words = Array(profile&.subject_entities || profile&.[](:subject_entities)) if words.empty?
        words.map(&:to_s).reject { |t| t.length < 3 }.uniq
      end
    end
  end
end
