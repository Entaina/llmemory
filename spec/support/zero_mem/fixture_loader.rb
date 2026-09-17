# frozen_string_literal: true

require "yaml"
require "digest"

module ZeroMem
  module FixtureLoader
    FIXTURE_ROOT = File.expand_path("../../fixtures/zero_mem", __dir__)
    CONVERSATIONS_DIR = File.join(FIXTURE_ROOT, "conversations")
    QUERIES_DIR = File.join(FIXTURE_ROOT, "queries")

    module_function

    def conversation_paths
      Dir.glob(File.join(CONVERSATIONS_DIR, "*.yml")).sort
    end

    def load_conversation(path)
      data = YAML.safe_load(File.read(path), permitted_classes: [Date, Time], aliases: true)
      data["source_path"] = path
      data
    end

    def load_all_conversations
      conversation_paths.map { |path| load_conversation(path) }
    end

    def load_query_sets
      retrieval = load_query_file("retrieval.yml")
      answer = load_query_file("answer.yml")
      { retrieval: retrieval, answer: answer }
    end

    def load_query_file(name)
      path = File.join(QUERIES_DIR, name)
      return [] unless File.file?(path)

      data = YAML.safe_load(File.read(path), permitted_classes: [Date, Time], aliases: true)
      data.is_a?(Array) ? data : Array(data["queries"])
    end

    def turns_by_id(conversation)
      map = {}
      Array(conversation["sessions"]).each do |session|
        Array(session["turns"]).each do |turn|
          map[turn["id"]] = turn.merge("session_id" => session["id"])
        end
      end
      map
    end

    def all_queries
      from_files = load_all_conversations.flat_map do |conv|
        Array(conv["queries"]).map do |q|
          q.merge(
            "conversation_id" => conv["id"],
            "language" => conv["language"],
            "workload_class" => conv["workload_class"],
            "conversation_path" => conv["source_path"]
          )
        end
      end
      sets = load_query_sets
      extra = (sets[:retrieval] + sets[:answer]).map do |q|
        conv = load_conversation_by_id(q["conversation_id"])
        q.merge(
          "language" => conv&.dig("language"),
          "workload_class" => conv&.dig("workload_class"),
          "conversation_path" => conv&.dig("source_path")
        )
      end
      (from_files + extra).uniq { |q| [q["conversation_id"], q["id"]] }
    end

    def load_conversation_by_id(id)
      load_all_conversations.find { |c| c["id"] == id }
    end

    def fixture_content_hashes
      conversation_paths.each_with_object({}) do |path, acc|
        rel = path.sub(%r{\A#{Regexp.escape(FIXTURE_ROOT)}/?}, "")
        acc[rel] = Digest::SHA256.hexdigest(File.read(path))
      end
    end

    def validate_coverage!(conversations = load_all_conversations)
      required = %w[
        local_fact multi_hop temporal current_state procedural conflict
      ]
      langs = %w[es en]
      matrix = Hash.new { |h, k| h[k] = {} }

      conversations.each do |conv|
        lang = conv["language"]
        workload = conv["workload_class"]
        next unless langs.include?(lang) && required.include?(workload)

        flags = matrix[[lang, workload]]
        flags[:present] = true
        flags[:revision] ||= conv["has_revision"] == true
        flags[:multi_session] ||= (conv["session_count"].to_i > 1)
        flags[:tool] ||= Array(conv["roles"]).map(&:to_s).include?("tool")
      end

      missing = []
      langs.each do |lang|
        required.each do |workload|
          missing << "#{lang}/#{workload}" unless matrix[[lang, workload]][:present]
        end
      end
      raise "Zero-Mem fixture matrix incomplete: #{missing.join(', ')}" if missing.any?

      conversations
    end
  end
end
