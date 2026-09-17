# frozen_string_literal: true

require "json"
require_relative "base"

module LocalBenchmark
  module Adapters
    # v1: interdependent subtasks as persistent QA (no full web gym).
    class MemoryArena < Base
      CONFIGS = %w[
        bundled_shopping
        progressive_search
        group_travel_planner
        formal_reasoning_math
        formal_reasoning_phys
      ].freeze

      def initialize(root: ENV["MEMORYARENA_DATASET_ROOT"],
                     config: ENV.fetch("MEMORYARENA_CONFIG", "bundled_shopping"))
        @root = root.to_s
        @config = config.to_s
      end

      def available?
        !@root.empty? && !jsonl_paths.empty?
      end

      def skip_reason
        "Set MEMORYARENA_DATASET_ROOT with JSONL for config #{CONFIGS.join('|')}"
      end

      def each_conversation
        return enum_for(:each_conversation) unless block_given?
        return unless available?

        jsonl_paths.each do |path|
          File.foreach(path).with_index do |line, idx|
            next if line.strip.empty?

            row = JSON.parse(line)
            yield normalize(row, idx, path)
          end
        end
      end

      private

      def jsonl_paths
        @jsonl_paths ||= begin
          direct = File.join(@root, "#{@config}.jsonl")
          return [direct] if File.file?(direct)

          Dir.glob(File.join(@root, "**", "*#{@config}*.jsonl")).sort
        end
      end

      def normalize(row, idx, path)
        questions = Array(row["questions"])
        answers = Array(row["answers"])
        backgrounds = row["backgrounds"] || row["background"]
        backgrounds = [backgrounds] unless backgrounds.is_a?(Array)

        sessions = [{
          "id" => "arena_ctx",
          "turns" => backgrounds.each_with_index.filter_map do |bg, bidx|
            next if bg.to_s.strip.empty?

            {
              "id" => "bg#{bidx + 1}",
              "role" => "user",
              "content" => bg.to_s
            }
          end
        }]

        queries = questions.each_with_index.map do |question, qidx|
          {
            "id" => "q#{qidx + 1}",
            "text" => question.to_s,
            "gold_answer" => answers[qidx].to_s,
            "question_type" => @config,
            "task_success" => nil
          }
        end

        {
          "id" => row["id"] || "arena_#{idx}",
          "language" => "en",
          "workload_class" => "memory_arena",
          "consolidate_after_hydrate" => true,
          "persist_subtask_answers" => true,
          "metadata" => { "source_path" => path },
          "sessions" => sessions,
          "queries" => queries
        }
      end
    end
  end
end
