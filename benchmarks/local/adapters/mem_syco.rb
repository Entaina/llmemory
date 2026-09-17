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
        !@root.empty? && File.file?(task_file)
      end

      def skip_reason
        "Set MEMSYCO_DATASET_ROOT with JSONL samples (MEMSYCO_TASK=#{TASKS.join('|')})"
      end

      def each_conversation
        return enum_for(:each_conversation) unless block_given?
        return unless available?

        File.foreach(task_file).with_index do |line, idx|
          next if line.strip.empty?

          row = JSON.parse(line)
          yield normalize(row, idx)
        end
      end

      private

      def task_file
        @task_file ||= begin
          direct = File.join(@root, "#{@task}.jsonl")
          return direct if File.file?(direct)

          hits = Dir.glob(File.join(@root, "**", "#{@task}.jsonl"))
          hits.first || direct
        end
      end

      def normalize(row, idx)
        memory_context = row["memory_context"] || row["retrieved_memory"] || row["context"]
        dialogue = row["dialogue"] || row["sessions"] || row["history"]
        sessions = if dialogue.is_a?(Array) && dialogue.first.is_a?(Hash) && dialogue.first["turns"]
                     dialogue
                   else
                     [{
                       "id" => "s1",
                       "turns" => Array(dialogue).map.with_index do |turn, tidx|
                         {
                           "id" => "t#{tidx + 1}",
                           "role" => turn["role"] || "user",
                           "content" => turn["content"] || turn["text"]
                         }
                       end
                     }]
                   end

        {
          "id" => row["id"] || "memsyco_#{idx}",
          "language" => "en",
          "workload_class" => "memsyco",
          "consolidate_after_hydrate" => true,
          "sessions" => sessions,
          "queries" => [
            {
              "id" => "q1",
              "text" => row["question"].to_s,
              "gold_answer" => row["reference"] || row["answer"],
              "question_type" => @task,
              "metadata" => { "memory_context" => memory_context }
            }
          ]
        }
      end
    end
  end
end
