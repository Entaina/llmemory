# frozen_string_literal: true

require_relative "base"

module Llmemory
  module Cli
    module Commands
      class Episodic < Commands::Base
        def option_parser(parser)
          parser.on("--limit N", Integer, "Max number of episodes (newest first)") { |v| @limit = v }
          parser.on("--store TYPE", "Storage type (memory|file|postgres|active_record)") { |v| @store_type = v }
        end

        def execute(argv, _opts)
          user_id = argv.first
          unless user_id
            $stderr.puts "Usage: llmemory episodes USER_ID [--limit N] [--store TYPE]"
            exit 1
          end

          storage = episodic_storage(@store_type)
          episodes = storage.list_episodes(user_id, limit: @limit)

          if episodes.empty?
            puts "No episodes for user #{user_id}."
            return
          end

          episodes.each do |e|
            id = e[:id] || e["id"]
            summary = e[:summary] || e["summary"]
            outcome = e[:outcome] || e["outcome"]
            importance = e[:importance] || e["importance"]
            steps = e[:steps] || e["steps"] || []
            puts "[#{id}] (importance: #{importance}; outcome: #{outcome || 'n/a'}) #{summary}"
            puts "  steps: #{Array(steps).size}"
          end
        end
      end
    end
  end
end
