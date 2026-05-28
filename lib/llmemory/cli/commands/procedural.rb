# frozen_string_literal: true

require_relative "base"

module Llmemory
  module Cli
    module Commands
      class Procedural < Commands::Base
        def option_parser(parser)
          parser.on("--limit N", Integer, "Max number of skills (newest first)") { |v| @limit = v }
          parser.on("--store TYPE", "Storage type (memory|file|postgres|active_record)") { |v| @store_type = v }
        end

        def execute(argv, _opts)
          user_id = argv.first
          unless user_id
            $stderr.puts "Usage: llmemory skills USER_ID [--limit N] [--store TYPE]"
            exit 1
          end

          storage = procedural_storage(@store_type)
          skills = storage.list_skills(user_id, limit: @limit)

          if skills.empty?
            puts "No skills for user #{user_id}."
            return
          end

          skills.each do |s|
            id = s[:id] || s["id"]
            name = s[:name] || s["name"]
            kind = s[:kind] || s["kind"]
            version = s[:version] || s["version"]
            succ = (s[:success_count] || s["success_count"] || 0).to_i
            fail = (s[:failure_count] || s["failure_count"] || 0).to_i
            total = succ + fail
            rate = total.zero? ? "n/a" : format("%.2f", succ.to_f / total)
            puts "[#{id}] #{name} v#{version} (#{kind}) — success rate: #{rate} (#{succ}/#{total})"
          end
        end
      end
    end
  end
end
