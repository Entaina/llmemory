# frozen_string_literal: true

require "llmemory"

module LocalBenchmark
  module Adapters
    module LocomoNormalizer
      module_function

      def normalize_locomo_sample(sample)
        conv = sample["conversation"] || {}
        sample_id = sample["sample_id"] || sample["id"] || "locomo"
        sessions = []
        session_idx = 1
        loop do
          key = "session_#{session_idx}"
          break unless conv[key]

          date_key = "session_#{session_idx}_date_time"
          occurred = conv[date_key]
          turns = Array(conv[key]).map do |turn|
            {
              "id" => turn["dia_id"],
              "role" => map_role(turn["speaker"], conv),
              "speaker" => turn["speaker"],
              "content" => turn["text"].to_s,
              "occurred_at" => normalize_occurred_at(occurred)
            }
          end
          sessions << { "id" => "s#{session_idx}", "turns" => turns }
          session_idx += 1
        end

        queries = Array(sample["qa"]).map.with_index do |qa, idx|
          {
            "id" => "q#{idx + 1}",
            "text" => qa["question"].to_s,
            "gold_answer" => qa["answer"].to_s,
            "gold_trace_ids" => Array(qa["evidence"]),
            "category" => qa["category"],
            "answer_type" => "text"
          }
        end

        {
          "id" => sample_id.to_s,
          "language" => "en",
          "workload_class" => "locomo",
          "session_count" => sessions.size,
          "has_revision" => false,
          "consolidate_mode" => "per_session",
          "sessions" => sessions,
          "queries" => queries
        }
      end

      def map_role(speaker, conv)
        speaker.to_s == conv["speaker_a"].to_s ? "user" : "assistant"
      end

      def normalize_occurred_at(raw)
        return nil if raw.nil?

        Llmemory.parse_occurred_at(raw)
      end
    end
  end
end
