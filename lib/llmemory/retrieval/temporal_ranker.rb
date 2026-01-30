# frozen_string_literal: true

module Llmemory
  module Retrieval
    class TemporalRanker
      def initialize(half_life_days: nil)
        @half_life_days = half_life_days || Llmemory.configuration.time_decay_half_life_days
      end

      def rank(candidates, now: Time.now)
        candidates.map do |c|
          score = (c[:score] || c["score"] || 1.0).to_f
          timestamp = c[:timestamp] || c["timestamp"]
          timestamp = Time.parse(timestamp.to_s) if timestamp.is_a?(String)
          age_days = timestamp ? (now - timestamp).to_i / 86400 : 0
          time_decay = 1.0 / (1.0 + (age_days.to_f / @half_life_days))
          final_score = score * time_decay
          c.merge(score: score, temporal_score: final_score, timestamp: timestamp)
        end.sort_by { |c| -(c[:temporal_score] || 0) }
      end
    end
  end
end
