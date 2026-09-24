# frozen_string_literal: true

require "json"
require "date"
require_relative "locomo_normalizer"

module LocalBenchmark
  module Adapters
    module LoCoMoPlusStitcher
      TIME_GAP_DAYS = {
        "one week later" => 7,
        "two weeks later" => 14,
        "about one week later" => 7,
        "about two weeks later" => 14,
        "about three weeks later" => 21,
        "about one month later" => 30,
        "about two months later" => 60,
        "about three months later" => 90,
        "about four months later" => 120,
        "about five months later" => 150,
        "about six months later" => 180
      }.freeze

      module_function

      def load_locomo10_samples(root)
        path = File.join(root, "locomo10.json")
        path = File.join(root, "data", "locomo10.json") unless File.file?(path)
        return [] unless File.file?(path)

        JSON.parse(File.read(path))
      end

      def stitch(row, idx, locomo_samples)
        base = locomo_samples[idx % locomo_samples.size]
        base_conv = LocomoNormalizer.normalize_locomo_sample(base)
        speaker_a = base.dig("conversation", "speaker_a") || "A"
        speaker_b = base.dig("conversation", "speaker_b") || "B"

        anchor_time = last_session_time(base_conv) || Time.utc(2023, 5, 8, 13, 56)
        gap_days = TIME_GAP_DAYS[row["time_gap"].to_s.downcase.strip] || 14
        cue_time = anchor_time + (gap_days * 86_400)

        cue_turns = parse_dialogue(row["cue_dialogue"], speaker_a, speaker_b, prefix: "cue", at: cue_time)

        sessions = base_conv["sessions"] + [
          { "id" => "cue", "turns" => cue_turns }
        ]

        constraints = {
          "cue_dialogue" => row["cue_dialogue"],
          "relation_type" => row["relation_type"],
          "time_gap" => row["time_gap"]
        }

        {
          "id" => "locomo_plus_#{idx}",
          "language" => "en",
          "workload_class" => "locomo_plus",
          "consolidate_mode" => "per_session",
          "sessions" => sessions,
          "queries" => [
            {
              "id" => "q1",
              "text" => trigger_question(row["trigger_query"]),
              "gold_answer" => row["trigger_query"].to_s,
              "gold_trace_ids" => cue_turns.map { |t| t["id"] },
              "question_type" => "locomo_plus_continuation",
              "metadata" => { "constraints" => constraints }
            }
          ]
        }
      end

      def last_session_time(conv)
        times = conv["sessions"].flat_map { |s| s["turns"] }.filter_map { |t| t["occurred_at"] }
        parsed = times.map { |t| t.is_a?(Time) ? t : Llmemory.parse_occurred_at(t) }.compact
        parsed.max
      end

      def trigger_question(text)
        lines = text.to_s.lines.map(&:strip).reject(&:empty?)
        last = lines.last.to_s
        last.sub(/\A[AB]:\s*/, "")
      end

      def parse_dialogue(text, speaker_a, speaker_b, prefix:, at:)
        Array(text.to_s.lines).map(&:strip).reject(&:empty?).each_with_index.map do |line, idx|
          speaker, content = if line.start_with?("A:")
                               [speaker_a, line.sub(/\AA:\s*/, "")]
                             elsif line.start_with?("B:")
                               [speaker_b, line.sub(/\AB:\s*/, "")]
                             else
                               [speaker_a, line]
                             end
          {
            "id" => "#{prefix}:#{idx + 1}",
            "role" => speaker.to_s == speaker_a.to_s ? "user" : "assistant",
            "speaker" => speaker,
            "content" => content,
            "occurred_at" => at
          }
        end
      end
    end
  end
end
