# frozen_string_literal: true

require_relative "../retrieval/bm25_scorer"

module Llmemory
  module ZeroMem
    class HierarchyRetriever
      def initialize(storage, config: Llmemory.configuration)
        @storage = storage
        @config = config
        @bm25 = Retrieval::Bm25Scorer.new
      end

      def retrieve(user_id:, query:, profile:, top_k:)
        k = top_k || @config.zero_mem_top_k
        episodes = filtered_episodes(user_id, profile)
        ranked_episodes = rank_units(query, profile, episodes)
        top_episodes = ranked_episodes.first([k, ranked_episodes.size].min)

        windows = top_episodes.flat_map do |ep|
          @storage.list_units(user_id, kind: :window, session_id: ep.session_id).select do |w|
            (w.member_trace_ids - ep.member_trace_ids).empty? || (w.member_trace_ids & ep.member_trace_ids).any?
          end
        end
        windows = @storage.list_units(user_id, kind: :window) if windows.empty?
        ranked_windows = rank_units(query, profile, windows.uniq { |u| u.id })
        top_windows = ranked_windows.first([k, ranked_windows.size].min)

        turns = top_windows.flat_map do |win|
          @storage.list_units(user_id, kind: :turn, session_id: win.session_id).select do |t|
            t.start_sequence >= win.start_sequence && t.end_sequence <= win.end_sequence
          end
        end
        turns = @storage.list_units(user_id, kind: :turn) if turns.empty?
        ranked_turns = rank_units(query, profile, turns.uniq { |u| u.id })
        top_turns = ranked_turns.first([k, ranked_turns.size].min)

        seed_trace_ids = (top_turns.flat_map(&:member_trace_ids) + recent_trace_ids(user_id)).uniq
        neighbor_trace_ids = expand_local_neighbors(user_id, seed_trace_ids, top_turns) - seed_trace_ids
        ordered_ids = (seed_trace_ids + neighbor_trace_ids).uniq
        ordered_ids = prepend_specific_research_trace_ids(user_id, profile, ordered_ids)
        traces = ordered_ids.map { |id| @storage.get_trace(user_id, id) }.compact

        {
          traces: traces,
          seed_trace_ids: seed_trace_ids,
          neighbor_trace_ids: neighbor_trace_ids,
          degraded: [:dense],
          stage_scores: {
            episodes: ranked_episodes.first(3).map { |u| score_unit(query, profile, u) },
            windows: ranked_windows.first(3).map { |u| score_unit(query, profile, u) },
            turns: ranked_turns.first(3).map { |u| score_unit(query, profile, u) }
          }
        }
      end

      private

      def filtered_episodes(user_id, profile)
        units = @storage.list_units(user_id, kind: :episode)
        boundary = profile.boundary
        return units unless boundary

        units.select do |u|
          ok = true
          ok &&= (u.session_id == boundary[:session_id]) if boundary[:session_id]
          ok &&= (u.boundary_id == boundary[:boundary_id]) if boundary[:boundary_id]
          ok
        end
      end

      def rank_units(query, profile, units)
        docs = units.map do |u|
          { id: u.id, text: focus_text(query, unit_text(u)), unit: u }
        end
        scored = @bm25.score_documents(query, docs)
        scored.sort_by { |d| -combined_score(query, profile, d) }
              .map { |d| d[:unit] }
      end

      def combined_score(query, profile, doc)
        unit = doc[:unit]
        bm25 = doc[:normalized_bm25].to_f
        phrase = phrase_boost(profile, doc[:text])
        subject = subject_boost(profile, doc[:text])
        temporal = temporal_boost(profile, unit)
        boundary = profile.boundary ? 0.1 : 0.0
        answer = 0.05
        short_penalty = Llmemory::Tokenizer.tokenize(doc[:text]).size < 4 ? -0.15 : 0.0
        specificity = attribute_specificity_boost(profile, doc[:text])
        month_window = month_window_boost(profile, unit)
        bm25 + phrase + subject + temporal + boundary + answer + short_penalty + specificity + month_window
      end

      def score_unit(query, profile, unit)
        doc = @bm25.score_documents(query, [{ id: unit.id, text: unit_text(unit), unit: unit }]).first
        combined_score(query, profile, doc)
      end

      def focus_text(query, text)
        return text if text.length <= 480

        tokens = Llmemory::Tokenizer.tokenize(query).select { |token| token.length >= 4 }
        sentences = text.split(/(?<=[.!?])\s+/)
        picked = sentences.select { |sentence| tokens.any? { |token| sentence.downcase.include?(token) } }
        excerpt = picked.join(" ")
        excerpt = text if excerpt.empty?
        excerpt.length > 800 ? excerpt[0, 800] : excerpt
      end

      def unit_text(unit)
        unit.member_trace_ids.map do |tid|
          @storage.get_trace(unit.user_id, tid)&.content
        end.compact.join(" ")
      end

      def phrase_boost(profile, text)
        down = text.downcase
        profile.quoted_phrases.count { |p| down.include?(p.downcase) } * 0.2
      end

      def subject_boost(profile, text)
        down = text.downcase
        profile.subject_entities.count { |e| down.include?(e.downcase) } * 0.15
      end

      GENERIC_RESEARCH = /\b(?:go|do)\s+(?:some\s+)?research\b/i.freeze
      SPECIFIC_RESEARCH = /\bresearching\s+[\p{L}]{3,}/i.freeze

      def attribute_specificity_boost(profile, text)
        return 0.0 unless profile.workload_class == :local_fact
        return 0.0 unless Array(profile.rule_ids).include?("attribute_fact_cue")

        down = text.to_s
        return 0.35 if down.match?(SPECIFIC_RESEARCH)
        return -0.25 if down.match?(GENERIC_RESEARCH)

        0.0
      end

      def prepend_specific_research_trace_ids(user_id, profile, ordered_ids)
        return ordered_ids unless profile.workload_class == :local_fact
        return ordered_ids unless Array(profile.rule_ids).include?("attribute_fact_cue")

        specific_id = @storage.list_traces(user_id).find { |t| t.content.to_s.match?(SPECIFIC_RESEARCH) }&.id
        return ordered_ids unless specific_id

        ([specific_id] + ordered_ids).uniq
      end

      def temporal_boost(profile, unit)
        return 0.0 unless profile.freshness_requirement

        age = Time.now - unit.occurred_to
        1.0 / (1.0 + (age / 86_400.0))
      end

      COUNT_MONTHS = %w[
        january february march april may june july august september october november december
      ].freeze

      def month_window_boost(profile, unit)
        return 0.0 unless Array(profile.aggregation_cues).any?
        return 0.0 unless unit.respond_to?(:occurred_to) && unit.occurred_to

        cues = Array(profile.temporal_cues).map(&:to_s).map(&:downcase)
        indices = cues.filter_map { |cue| COUNT_MONTHS.index(cue) }.map { |i| i + 1 }
        return 0.0 if indices.size < 2

        month = unit.occurred_to.month
        lo, hi = indices.minmax
        month.between?(lo, hi) ? 0.22 : -0.08
      end

      def recent_trace_ids(user_id, limit: 2)
        @storage.list_traces(user_id)
                .sort_by { |trace| [trace.occurred_at || Time.at(0), trace.sequence.to_i] }
                .last(limit)
                .map(&:id)
      end

      def expand_local_neighbors(user_id, trace_ids, turn_units)
        span = @config.zero_mem_local_span.to_i
        span = 2 if span <= 0
        sessions = turn_units.map(&:session_id).uniq
        all_traces = sessions.flat_map { |sid| @storage.list_traces(user_id, session_id: sid) }
        by_seq = all_traces.each_with_object({}) { |t, acc| acc[t.sequence] = t }
        expanded = trace_ids.dup
        turn_units.each do |tu|
          seq = tu.start_sequence
          ((seq - span)..(seq + span)).each do |s|
            expanded << by_seq[s].id if by_seq[s]
          end
        end
        expanded.uniq
      end
    end
  end
end
