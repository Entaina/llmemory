# frozen_string_literal: true

require "json"
require "llmemory"
require_relative "base"

module LocalBenchmark
  module Adapters
    class GroupMemBench < Base
      def initialize(root: ENV["GROUPMEMBENCH_DATASET_ROOT"],
                     domain: ENV.fetch("GROUPMEMBENCH_DOMAIN", "Finance"),
                     qtype: ENV.fetch("GROUPMEMBENCH_QTYPE", "multi_hop"))
        @root = root.to_s
        @domain = domain.to_s
        @qtype = qtype.to_s
      end

      def available?
        !@root.empty? && File.file?(conversation_path) && File.file?(questions_path)
      end

      def skip_reason
        "Set GROUPMEMBENCH_DATASET_ROOT (UCSB-NLP-Chang/GroupMemBench checkout)"
      end

      def each_conversation
        return enum_for(:each_conversation) unless block_given?
        return unless available?

        conv_data = JSON.parse(File.read(conversation_path))
        channel_id = conv_data["channel_id"] || "#{@domain}_channel"
        turns = cap_turns(normalize_channel_turns(conv_data))

        File.foreach(questions_path).with_index do |line, idx|
          next if line.strip.empty?

          qa = JSON.parse(line)
          yield({
            "id" => "#{channel_id}_#{@qtype}_#{idx}",
            "language" => "en",
            "workload_class" => "groupmembench",
            "consolidate_mode" => "per_session",
            "sessions" => [{ "id" => channel_id, "turns" => turns }],
            "queries" => [
              {
                "id" => qa["id"] || "q#{idx + 1}",
                "text" => qa["question"].to_s,
                "gold_answer" => qa["answer"] || qa["reference"],
                "question_type" => @qtype,
                "gold_trace_ids" => Array(qa["evidence_turn_ids"])
              }
            ]
          })
        end
      end

      private

      def conversation_path
        @conversation_path ||= begin
          direct = File.join(@root, "data", "final", @domain, "synthetic_domain_channels_rolevariants_#{@domain}.json")
          return direct if File.file?(direct)

          direct = File.join(@root, "data", @domain, "synthetic_domain_channels_rolevariants_#{@domain}.json")
          return direct if File.file?(direct)

          hits = Dir.glob(File.join(@root, "**", "*#{@domain}*.json"))
          hits.find { |p| p.include?("channel") } || hits.first || direct
        end
      end

      def questions_path
        @questions_path ||= begin
          direct = File.join(@root, "questions", @domain, "#{@qtype}.jsonl")
          return direct if File.file?(direct)

          Dir.glob(File.join(@root, "**", @domain, "#{@qtype}.jsonl")).first ||
            File.join(@root, "questions", @domain, "#{@qtype}.jsonl")
        end
      end

      def normalize_channel_turns(conv_data)
        messages = conv_data["messages"] || conv_data["turns"] || conv_data["posts"] || []
        if messages.empty? && conv_data.is_a?(Hash)
          arrays = conv_data.values.select { |v| v.is_a?(Array) && !v.empty? }
          messages = arrays.max_by(&:size) || []
        end

        Array(messages).each_with_index.map do |msg, idx|
          speaker = msg["speaker"] || msg["user"] || msg["author"] || "user"
          body = msg["content"] || msg["text"] || msg["message"]
          {
            "id" => msg["msg_node"] || msg["id"] || "t#{idx + 1}",
            "role" => "user",
            "speaker" => speaker,
            "content" => "#{speaker}: #{body}",
            "occurred_at" => normalize_occurred_at(msg["timestamp"])
          }
        end
      end

      def normalize_occurred_at(raw)
        return nil if raw.nil?

        Llmemory.parse_occurred_at(raw)
      end

      def cap_turns(turns)
        max = ENV["GROUPMEMBENCH_MAX_TURNS"].to_i
        return turns if max <= 0 || turns.size <= max

        # Keep the most recent channel turns (questions usually reference late context).
        turns.last(max)
      end
    end
  end
end
