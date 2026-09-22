# frozen_string_literal: true

require "json"
require_relative "base"

module LocalBenchmark
  module Adapters
    # Loads exported MemoryAgentBench JSON/JSONL (Accurate Retrieval, FactConsolidation).
    class MemoryAgentBench < Base
      SUBSETS = %w[Accurate_Retrieval FactConsolidation].freeze
      CHUNK_SIZE = 1200
      CHUNKS_PER_SESSION = 5

      def initialize(root: ENV["MEMORYAGENTBENCH_DATASET_ROOT"],
                     subset: ENV.fetch("MEMORYAGENTBENCH_SUBSET", "Accurate_Retrieval"))
        @root = root.to_s
        @subset = subset.to_s
      end

      def available?
        !@root.empty? && !input_paths.empty?
      end

      def skip_reason
        "Set MEMORYAGENTBENCH_DATASET_ROOT with JSON/JSONL for #{SUBSETS.join(', ')}"
      end

      def conversations(limit: nil)
        max_sessions = ENV.fetch("MEMORYAGENTBENCH_MAX_SESSIONS", "40").to_i
        list = each_conversation.to_a
        list = Canonical.limit_conversations(list, limit: limit) if limit
        list.each { |c| Canonical.validate!(c) }
        list.map { |conv| cap_sessions(conv, max_sessions) }
      end

      def each_conversation
        return enum_for(:each_conversation) unless block_given?
        return unless available?

        input_paths.each_with_index do |path, file_idx|
          each_record(path).with_index do |record, rec_idx|
            yield normalize_record(record, file_idx, rec_idx)
          end
        end
      end

      def cap_sessions(conv, max_sessions)
        sessions = Array(conv["sessions"])
        return conv if sessions.size <= max_sessions

        dup = conv.dup
        dup["sessions"] = sessions.first(max_sessions)
        dup
      end

      private

      def input_paths
        return @input_paths if defined?(@input_paths)

        paths = []
        subset_dir = File.join(@root, @subset)
        if File.directory?(subset_dir)
          paths = Dir.glob(File.join(subset_dir, "**/*.{json,jsonl}"))
        else
          paths = Dir.glob(File.join(@root, "**/*#{@subset}*.{json,jsonl}"))
        end
        @input_paths = paths.sort
      end

      def each_record(path)
        return enum_for(:each_record, path) unless block_given?

        if path.end_with?(".jsonl")
          File.foreach(path) { |line| yield JSON.parse(line) if line.strip != "" }
        else
          data = JSON.parse(File.read(path))
          if data.is_a?(Array)
            data.each { |row| yield row }
          elsif data.is_a?(Hash) && data["data"]
            Array(data["data"]).each { |row| yield row }
          else
            yield data
          end
        end
      end

      def normalize_record(record, file_idx, rec_idx)
        chunks = extract_chunks(record)
        sessions = build_chunk_sessions(chunks)

        questions = Array(record["questions"] || record["qa_pairs"] || [record])
        queries = questions.filter_map.with_index do |qa, qidx|
          qtext = qa["question"] || qa["query"] || record["question"]
          ans = qa["answer"] || qa["gold_answer"] || record["answer"]
          next if qtext.to_s.empty?

          {
            "id" => qa["qa_pair_id"] || qa["id"] || "q#{qidx + 1}",
            "text" => qtext.to_s,
            "gold_answer" => ans.to_s,
            "gold_trace_ids" => [],
            "question_type" => @subset
          }
        end

        {
          "id" => record["id"] || record["sample_id"] || "mab_#{file_idx}_#{rec_idx}",
          "language" => "en",
          "workload_class" => "memoryagentbench",
          "session_count" => 1,
          "has_revision" => @subset == "FactConsolidation",
          "consolidate_mode" => "per_session",
          "sessions" => sessions,
          "queries" => queries
        }
      end

      def build_chunk_sessions(chunks)
        chunks.each_slice(CHUNKS_PER_SESSION).with_index.map do |group, sidx|
          {
            "id" => "s#{sidx + 1}",
            "turns" => group.each_with_index.map do |chunk, tidx|
              {
                "id" => "s#{sidx + 1}t#{tidx + 1}",
                "role" => "user",
                "content" => chunk.to_s
              }
            end
          }
        end
      end

      def extract_chunks(record)
        if record["chunks"].is_a?(Array)
          return record["chunks"].map { |c| c.is_a?(Hash) ? c["text"] || c["content"] : c }
        end
        if record["context_chunks"].is_a?(Array)
          return record["context_chunks"].map { |c| c["text"] || c["content"] || c }
        end
        if record["source_text"].is_a?(String)
          return record["source_text"].scan(/.{1,#{CHUNK_SIZE}}/m)
        end
        if record["messages"].is_a?(Array)
          return record["messages"].map { |m| "#{m['role']}: #{m['content']}" }
        end

        text = record["context"] || record["text"] || record.to_json
        text.to_s.scan(/.{1,#{CHUNK_SIZE}}/m)
      end
    end
  end
end
