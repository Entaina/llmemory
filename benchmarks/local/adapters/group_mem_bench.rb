# frozen_string_literal: true

require "json"
require "llmemory"
require_relative "base"

module LocalBenchmark
  module Adapters
    class GroupMemBench < Base
      STOPWORDS = %w[
        a an the is are was were be been being what when where who which how many much
        for to of in on at by with and or from as that this it its their there about
      ].freeze

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
        project_messages = extract_project_messages(conv_data)

        File.foreach(questions_path).with_index do |line, idx|
          next if line.strip.empty?

          qa = JSON.parse(line)
          question = qa["question"].to_s
          sessions = build_project_sessions(project_messages, channel_id, question)
          sessions = rank_sessions_for_question(sessions, question)
          max_consolidate = ENV.fetch("GROUPMEMBENCH_MAX_CONSOLIDATE_SESSIONS", "2").to_i
          sessions = sessions.first(max_consolidate) if max_consolidate.positive?

          yield({
            "id" => "#{channel_id}_#{@qtype}_#{idx}",
            "language" => "en",
            "workload_class" => "groupmembench",
            "consolidate_mode" => "per_session",
            "sessions" => sessions,
            "queries" => [
              {
                "id" => qa["id"] || "q#{idx + 1}",
                "text" => question,
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

      def extract_project_messages(conv_data)
        messages = conv_data["messages"] || conv_data["turns"] || conv_data["posts"]
        return { "channel" => messages } if messages.is_a?(Array) && !messages.empty?

        return {} unless conv_data.is_a?(Hash)

        conv_data.each_with_object({}) do |(key, value), acc|
          next unless value.is_a?(Array) && !value.empty?

          acc[key.to_s] = value
        end
      end

      def build_project_sessions(project_messages, channel_id, question)
        keywords = question_keywords(question)
        project_messages.map do |project, messages|
          turns = normalize_messages(messages, project: project, channel: channel_id)
          turns = select_turns_for_question(turns, keywords)
          {
            "id" => session_id_for(project),
            "project" => project,
            "turns" => turns
          }
        end.reject { |s| s["turns"].empty? }
      end

      def session_id_for(project)
        slug = project.to_s.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/^_|_$/, "")
        slug.empty? ? "project" : slug[0, 64]
      end

      def normalize_messages(messages, project:, channel:)
        Array(messages).each_with_index.map do |msg, idx|
          speaker = msg["speaker"] || msg["user"] || msg["author"] || "user"
          body = msg["content"] || msg["text"] || msg["message"]
          {
            "id" => msg["msg_node"] || msg["id"] || "t#{idx + 1}",
            "role" => "user",
            "speaker" => speaker,
            "content" => "#{speaker}: #{body}",
            "occurred_at" => normalize_occurred_at(msg["timestamp"]),
            "metadata" => { "project" => project, "channel" => channel }
          }
        end
      end

      def question_keywords(question)
        question.downcase.scan(/[a-z0-9]{3,}/).reject { |w| STOPWORDS.include?(w) }.uniq
      end

      def rank_sessions_for_question(sessions, question)
        keywords = question_keywords(question)
        sessions.sort_by do |session|
          texts = session["turns"].map { |t| t["content"].to_s.downcase }
          best = texts.map { |text| keywords.count { |kw| text.include?(kw) } }.max || 0
          total = texts.sum { |text| keywords.count { |kw| text.include?(kw) } }
          [-best, -total, session["id"].to_s]
        end
      end

      def select_turns_for_question(turns, keywords)
        max = ENV["GROUPMEMBENCH_MAX_TURNS"].to_i
        max = 80 if max <= 0
        return turns.last(max) if keywords.empty?

        turn_index = turns.each_with_index.to_h { |t, i| [t["id"], i] }
        scored = turns.each_with_index.map do |turn, idx|
          text = turn["content"].to_s.downcase
          score = keywords.count { |kw| text.include?(kw) }
          [turn, score, idx]
        end
        hits = scored.select { |_, score, _| score.positive? }.sort_by { |_, score, _| -score }
        pool = hits.empty? ? turns.last(max) : expand_hit_window(turns, hits, max)
        pool.sort_by { |t| turn_index[t["id"]] || 0 }
      end

      def expand_hit_window(turns, hits, max)
        chosen = {}
        hits.each do |turn, score, idx|
          break if chosen.size >= max

          chosen[turn["id"]] = turn
          next unless score >= 2

          ((idx - 2)..(idx + 2)).each do |nidx|
            break if chosen.size >= max
            next if nidx.negative? || nidx >= turns.size

            neighbor = turns[nidx]
            chosen[neighbor["id"]] = neighbor
          end
        end
        chosen.values
      end

      def normalize_occurred_at(raw)
        return nil if raw.nil?

        Llmemory.parse_occurred_at(raw)
      end
    end
  end
end
