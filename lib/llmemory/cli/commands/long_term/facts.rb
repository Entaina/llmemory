# frozen_string_literal: true

require_relative "../base"

module Llmemory
  module Cli
    module Commands
      module LongTerm
        class Facts < Commands::Base
          def option_parser(parser)
            parser.on("--category CATEGORY", "Filter by category") { |v| @category = v }
            parser.on("--limit N", Integer, "Max number of items") { |v| @limit = v }
            parser.on("--store TYPE", "Storage type") { |v| @store_type = v }
          end

          def execute(argv, _opts)
            user_id = argv.first
            unless user_id
              $stderr.puts "Usage: llmemory facts USER_ID [--category CATEGORY] [--limit N]"
              exit 1
            end

            storage = file_based_storage(@store_type)
            items = storage.list_items(user_id: user_id, category: @category, limit: @limit)

            if items.empty?
              puts "No facts found for user #{user_id}."
              return
            end

            items.each do |i|
              cat = i[:category] || i["category"]
              content = (i[:content] || i["content"]).to_s
              created = i[:created_at] || i["created_at"]
              puts "[#{cat}] #{content} (#{created})"
            end
          end
        end
      end
    end
  end
end
