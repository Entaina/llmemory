# frozen_string_literal: true

require_relative "../base"

module Llmemory
  module Cli
    module Commands
      module LongTerm
        class Categories < Commands::Base
          def option_parser(parser)
            parser.on("--store TYPE", "Storage type") { |v| @store_type = v }
          end

          def execute(argv, _opts)
            user_id = argv.first
            unless user_id
              $stderr.puts "Usage: llmemory categories USER_ID"
              exit 1
            end

            storage = file_based_storage(@store_type)
            categories = storage.list_categories(user_id)

            if categories.empty?
              puts "No categories found for user #{user_id}."
            else
              categories.each { |c| puts c }
            end
          end
        end
      end
    end
  end
end
