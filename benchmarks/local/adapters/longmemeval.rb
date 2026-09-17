# frozen_string_literal: true

require "json"
require_relative "base"

module LocalBenchmark
  module Adapters
    class LongMemEval < Base
      SPLITS = {
        "oracle" => "longmemeval_oracle.json",
        "s" => "longmemeval_s_cleaned.json",
        "s_legacy" => "longmemeval_s.json"
      }.freeze

      def initialize(root: ENV["LONGMEMEVAL_DATASET_ROOT"], split: ENV.fetch("LONGMEMEVAL_SPLIT", "oracle"))
        @root = root.to_s
        @split = split.to_s
      end

      def available?
        !@root.empty? && File.file?(dataset_path)
      end

      def skip_reason
        "Set LONGMEMEVAL_DATASET_ROOT with #{SPLITS[@split] || @split}"
      end

      def each_conversation
        return enum_for(:each_conversation) unless block_given?
        return unless available?

        records = JSON.parse(File.read(dataset_path))
        Array(records).each_with_index do |record, idx|
          yield normalize_record(record, idx)
        end
      end

      private

      def dataset_path
        name = SPLITS[@split] || @split
        File.join(@root, name)
      end

      def normalize_record(record, idx)
        sessions = []
        Array(record["haystack_sessions"]).each_with_index do |session_turns, sidx|
          date = Array(record["haystack_dates"])[sidx]
          sid = Array(record["haystack_session_ids"])[sidx] || "hs#{sidx + 1}"
          turns = Array(session_turns).each_with_index.map do |turn, tidx|
            {
              "id" => "#{sid}:t#{tidx + 1}",
              "role" => turn["role"].to_s == "assistant" ? "assistant" : "user",
              "content" => turn["content"].to_s,
              "occurred_at" => date,
              "has_answer" => turn["has_answer"]
            }
          end
          sessions << { "id" => sid.to_s, "turns" => turns }
        end

        gold_sessions = Array(record["answer_session_ids"]).map(&:to_s)
        gold_trace_ids = sessions.flat_map do |sess|
          next [] unless gold_sessions.include?(sess["id"])

          sess["turns"].select { |t| t["has_answer"] }.map { |t| t["id"] }
        end
        gold_trace_ids = sessions.flat_map { |s| s["turns"].map { |t| t["id"] } } if gold_trace_ids.empty?

        {
          "id" => record["question_id"] || "lme_#{idx}",
          "language" => "en",
          "workload_class" => "longmemeval",
          "question_type" => record["question_type"],
          "session_count" => sessions.size,
          "has_revision" => record["question_type"].to_s.include?("update"),
          "consolidate_mode" => "per_session",
          "sessions" => sessions,
          "queries" => [
            {
              "id" => "q1",
              "text" => record["question"].to_s,
              "gold_answer" => record["answer"].to_s,
              "gold_trace_ids" => gold_trace_ids,
              "question_type" => record["question_type"]
            }
          ]
        }
      end
    end
  end
end
