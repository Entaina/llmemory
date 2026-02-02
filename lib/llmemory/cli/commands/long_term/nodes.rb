# frozen_string_literal: true

require_relative "../base"

module Llmemory
  module Cli
    module Commands
      module LongTerm
        class Nodes < Commands::Base
          def option_parser(parser)
            parser.on("--type TYPE", "Filter by entity type") { |v| @entity_type = v }
            parser.on("--limit N", Integer, "Max number of nodes") { |v| @limit = v }
            parser.on("--store TYPE", "Storage type (memory, active_record)") { |v| @store_type = v }
          end

          def execute(argv, _opts)
            user_id = argv.first
            unless user_id
              $stderr.puts "Usage: llmemory nodes USER_ID [--type TYPE] [--limit N]"
              exit 1
            end

            storage = graph_based_storage(@store_type)
            nodes = storage.list_nodes(user_id, entity_type: @entity_type, limit: @limit)

            if nodes.empty?
              puts "No nodes found for user #{user_id}."
              return
            end

            nodes.each do |n|
              id = n.respond_to?(:id) ? n.id : n[:id]
              type = n.respond_to?(:entity_type) ? n.entity_type : n[:entity_type]
              name = n.respond_to?(:name) ? n.name : n[:name]
              puts "#{id} [#{type}] #{name}"
            end
          end
        end
      end
    end
  end
end
