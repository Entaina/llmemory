# frozen_string_literal: true

require "json"
require_relative "base"

module LocalBenchmark
  module Adapters
    class LoCoMoPlus < Base
      def initialize(root: ENV["LOCOMO_PLUS_DATASET_ROOT"])
        @root = root.to_s
      end

      def available?
        !@root.empty? && !json_paths.empty?
      end

      def skip_reason
        "Set LOCOMO_PLUS_DATASET_ROOT to xjtuleeyf/Locomo-Plus data checkout"
      end

      def each_conversation
        return enum_for(:each_conversation) unless block_given?
        return unless available?

        json_paths.each do |path|
          data = JSON.parse(File.read(path))
          Array(data.is_a?(Array) ? data : [data]).each { |row| yield normalize(row, path) }
        end
      end

      private

      def json_paths
        @json_paths ||= Dir.glob(File.join(@root, "**/*.json")).sort
      end

      def normalize(row, path)
        sessions = normalize_sessions(row)
        constraints = row["constraints"] || row["implicit_constraints"] || row["constraint_text"]
        queries = Array(row["questions"] || row["qa"] || [row]).map.with_index do |qa, idx|
          {
            "id" => qa["id"] || "q#{idx + 1}",
            "text" => (qa["question"] || qa["query"] || qa["trigger"]).to_s,
            "gold_answer" => (qa["answer"] || qa["reference"] || qa["expected"]).to_s,
            "gold_trace_ids" => Array(qa["evidence"] || qa["gold_trace_ids"]),
            "metadata" => {
              "constraints" => constraints,
              "source_path" => path
            }
          }
        end

        {
          "id" => row["id"] || row["sample_id"] || File.basename(path, ".json"),
          "language" => "en",
          "workload_class" => "locomo_plus",
          "consolidate_after_hydrate" => true,
          "sessions" => sessions,
          "queries" => queries
        }
      end

      def normalize_sessions(row)
        if row["sessions"].is_a?(Array)
          return row["sessions"]
        end
        [{
          "id" => "s1",
          "turns" => Array(row["turns"] || row["dialogue"]).map.with_index do |turn, idx|
            {
              "id" => turn["id"] || "t#{idx + 1}",
              "role" => turn["role"] || "user",
              "content" => turn["content"] || turn["text"]
            }
          end
        }]
      end
    end
  end
end
