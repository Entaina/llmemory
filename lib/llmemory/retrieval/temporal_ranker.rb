# frozen_string_literal: true

module Llmemory
  module Retrieval
    class TemporalRanker
      def initialize(half_life_days: nil, importance_weight: nil)
        @half_life_days = half_life_days || Llmemory.configuration.time_decay_half_life_days
        @importance_weight = importance_weight || Llmemory.configuration.importance_weight
      end

      def rank(candidates, now: nil, temporal_query: false)
        reference_now = if temporal_query
                          now || corpus_reference_time(candidates) || Time.now
                        else
                          now || Time.now
                        end
        half_life = @half_life_days.to_f
        half_life = 30.0 if half_life <= 0
        lambda_val = Math.log(2) / half_life
        weight = [@importance_weight.to_f, 0.0].max
        skip_decay = temporal_query

        candidates.map do |c|
          score = (c[:score] || c["score"] || 1.0).to_f
          timestamp = c[:timestamp] || c["timestamp"]
          timestamp = Time.parse(timestamp.to_s) if timestamp.is_a?(String)
          age_days = timestamp ? [(reference_now - timestamp) / 86_400.0, 0.0].max : 0.0

          time_decay = if skip_decay || c[:evergreen] || c["evergreen"]
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

      def corpus_reference_time(candidates)
        times = candidates.filter_map do |c|
          ts = c[:timestamp] || c["timestamp"]
          ts = Time.parse(ts.to_s) if ts.is_a?(String)
          ts
        end
        times.max
      end

      # Missing importance is neutral (1.0) so candidates that carry no
      # importance signal (resources, graph edges) are never penalised.
      def normalize_importance(value)
        return 1.0 if value.nil?
        [[value.to_f, 0.0].max, 1.0].min
      end
    end
  end
end
