# frozen_string_literal: true

require "json"
require_relative "base"

module LocalBenchmark
  module Adapters
    class Mem2Act < Base
      def initialize(root: ENV["MEM2ACT_DATASET_ROOT"], file: ENV.fetch("MEM2ACT_QA_FILE", "qa_dataset.jsonl"))
        @root = root.to_s
        @file = file
      end

      def available?
        !@root.empty? && File.file?(qa_path)
      end

      def skip_reason
        "Set MEM2ACT_DATASET_ROOT with qa_dataset.jsonl (Cantaloupe-M/Mem2ActBench)"
      end

      def each_conversation
        return enum_for(:each_conversation) unless block_given?
        return unless available?

        File.foreach(qa_path).with_index do |line, idx|
          next if line.strip.empty?

          row = JSON.parse(line)
          yield normalize(row, idx)
        end
      end

      private

      def qa_path
        File.join(@root, @file)
      end

      def normalize(row, idx)
        chain = Array(row["evolution_chain"] || row["memory_chain"] || [])
        sessions = [{
          "id" => "mem_chain",
          "turns" => chain.each_with_index.map do |fact, fidx|
            content = fact.is_a?(Hash) ? (fact["text"] || fact["fact"] || fact.to_json) : fact.to_s
            {
              "id" => fact.is_a?(Hash) ? (fact["fact_id"] || "f#{fidx + 1}") : "f#{fidx + 1}",
              "role" => "user",
              "content" => content
            }
          end
        }]

        tool = row["tool_call"] || {}
        schema = row["target_tool_schema"] || {}

        {
          "id" => row["qa_id"] || "mem2act_#{idx}",
          "language" => "en",
          "workload_class" => "mem2act",
          "consolidate_after_hydrate" => true,
          "sessions" => sessions,
          "queries" => [
            {
              "id" => "q1",
              "text" => row["query"].to_s,
              "gold_answer" => tool.to_json,
              "question_type" => "tool_call",
              "metadata" => {
                "tool_name" => tool["name"],
                "tool_arguments" => tool["arguments"] || {},
                "tool_schema" => schema
              }
            }
          ]
        }
      end
    end
  end
end
