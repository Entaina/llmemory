# frozen_string_literal: true

require_relative "../base"

module Llmemory
  module Cli
    module Commands
      module LongTerm
        class Resources < Commands::Base
          def option_parser(parser)
            parser.on("--limit N", Integer, "Max number of resources") { |v| @limit = v }
            parser.on("--store TYPE", "Storage type") { |v| @store_type = v }
          end

          def execute(argv, _opts)
            user_id = argv.first
            unless user_id
              $stderr.puts "Usage: llmemory resources USER_ID [--limit N]"
              exit 1
            end

            storage = file_based_storage(@store_type)
            resources = storage.list_resources(user_id: user_id, limit: @limit)

            if resources.empty?
              puts "No resources found for user #{user_id}."
              return
            end

            resources.each do |r|
              id = r[:id] || r["id"]
              text = (r[:text] || r["text"]).to_s
              text = text[0, 150] + "..." if text.length > 150
              created = r[:created_at] || r["created_at"]
              puts "#{id}: #{text} (#{created})"
            end
          end
        end
      end
    end
  end
end
