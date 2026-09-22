# frozen_string_literal: true

require "json"
require_relative "base"

module LocalBenchmark
  module Adapters
    class MemSyco < Base
      TASKS = %w[
        personalized_memory_use
        valid_memory_selection
        memory_evidence_conflict
        contextual_scope_control
        objective_fact_judgment
      ].freeze

      def initialize(root: ENV["MEMSYCO_DATASET_ROOT"], task: ENV.fetch("MEMSYCO_TASK", "personalized_memory_use"))
        @root = root.to_s
        @task = task.to_s
      end

      def available?
        return false if @root.empty?

        active_tasks.all? { |t| File.file?(task_file(t)) }
      end

      def skip_reason
        "Set MEMSYCO_DATASET_ROOT with JSONL samples (MEMSYCO_TASK=#{TASKS.join('|')}|all)"
      end

      def each_conversation
        return enum_for(:each_conversation) unless block_given?
        return unless available?

        active_tasks.each do |task|
          File.foreach(task_file(task)).with_index do |line, idx|
            next if line.strip.empty?

            row = JSON.parse(line)
            yield normalize(row, idx, task)
          end
        end
      end

      private

      def active_tasks
        @task == "all" ? TASKS : [@task]
      end

      def task_file(task = @task)
        direct = File.join(@root, "#{task}.jsonl")
        return direct if File.file?(direct)

        hits = Dir.glob(File.join(@root, "**", "#{task}.jsonl"))
        hits.first || direct
      end

      def normalize(row, idx, task)
        evaluation = row["evaluation"] || {}
        memory = row["memory"] || {}
        memory_items = Array(memory["items"])
        memory_context = row["memory_context"] || row["retrieved_memory"] || row["context"]
        dialogue = row["dialogue"] || row["sessions"] || row["history"]

        dialogue_sessions = if dialogue.is_a?(Array) && dialogue.first.is_a?(Hash) && dialogue.first["turns"]
                              dialogue
                            else
                              [{
                                "id" => "dialogue",
                                "turns" => Array(dialogue).map.with_index do |turn, tidx|
                                  {
                                    "id" => "t#{tidx + 1}",
                                    "role" => turn["role"] || "user",
                                    "content" => turn["content"] || turn["text"]
                                  }
                                end
                              }]
                            end

        memory_session = if memory_items.any?
                             {
                               "id" => "memory_items",
                               "turns" => memory_items.map.with_index do |item, midx|
                                 content = item.is_a?(Hash) ? (item["content"] || item.to_json) : item.to_s
                                 {
                                   "id" => "mem#{midx + 1}",
                                   "role" => "assistant",
                                   "content" => content
                                 }
                               end
                             }
                           end

        sessions = [memory_session, *dialogue_sessions].compact

        {
          "id" => "#{row['id'] || "memsyco_#{idx}"}_#{task}",
          "language" => "en",
          "workload_class" => "memsyco",
          "consolidate_after_hydrate" => true,
          "sessions" => sessions,
          "queries" => [
            {
              "id" => "q1",
              "text" => row["question"].to_s,
              "gold_answer" => evaluation["reference_answer"] || row["reference"] || row["answer"],
              "question_type" => task,
              "metadata" => {
                "memory_context" => memory_context,
                "rubric" => evaluation["rubric"],
                "memory_policy" => memory["policy"],
                "memory_items" => memory_items
              }
            }
          ]
        }
      end
    end
  end
end
