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

        trace_ids = top_turns.flat_map(&:member_trace_ids)
        trace_ids = expand_local_neighbors(user_id, trace_ids, top_turns)
        traces = trace_ids.map { |id| @storage.get_trace(user_id, id) }.compact

        {
          traces: traces,
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
          { id: u.id, text: unit_text(u), unit: u }
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
        bm25 + phrase + subject + temporal + boundary + answer
      end

      def score_unit(query, profile, unit)
        doc = @bm25.score_documents(query, [{ id: unit.id, text: unit_text(unit), unit: unit }]).first
        combined_score(query, profile, doc)
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

      def temporal_boost(profile, unit)
        return 0.0 unless profile.freshness_requirement

        age = Time.now - unit.occurred_to
        1.0 / (1.0 + (age / 86_400.0))
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
