# frozen_string_literal: true

module Llmemory
  module Retrieval
    class TemporalRanker
      def initialize(half_life_days: nil, importance_weight: nil)
        @half_life_days = half_life_days || Llmemory.configuration.time_decay_half_life_days
        @importance_weight = importance_weight || Llmemory.configuration.importance_weight
      end

      def rank(candidates, now: Time.now)
        lambda_val = Math.log(2) / @half_life_days.to_f
        weight = [@importance_weight.to_f, 0.0].max

        candidates.map do |c|
          score = (c[:score] || c["score"] || 1.0).to_f
          timestamp = c[:timestamp] || c["timestamp"]
          timestamp = Time.parse(timestamp.to_s) if timestamp.is_a?(String)
          age_days = timestamp ? (now - timestamp).to_i / 86400 : 0

          time_decay = if c[:evergreen] || c["evergreen"]
            1.0
          else
            Math.exp(-lambda_val * age_days.to_f)
          end

          importance = normalize_importance(c[:importance] || c["importance"])
          importance_factor = importance**weight

          final_score = score * time_decay * importance_factor
          c.merge(score: score, importance: importance, temporal_score: final_score, timestamp: timestamp)
        end.sort_by { |c| -(c[:temporal_score] || 0) }
      end

      private

      # Missing importance is neutral (1.0) so candidates that carry no
      # importance signal (resources, graph edges) are never penalised.
      def normalize_importance(value)
        return 1.0 if value.nil?
        [[value.to_f, 0.0].max, 1.0].min
      end
    end
  end
end
