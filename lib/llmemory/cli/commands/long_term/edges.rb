# frozen_string_literal: true

require_relative "../base"

module Llmemory
  module Cli
    module Commands
      module LongTerm
        class Edges < Commands::Base
          def option_parser(parser)
            parser.on("--subject NODE_ID", "Filter by subject node") { |v| @subject_id = v }
            parser.on("--limit N", Integer, "Max number of edges") { |v| @limit = v }
            parser.on("--store TYPE", "Storage type") { |v| @store_type = v }
          end

          def execute(argv, _opts)
            user_id = argv.first
            unless user_id
              $stderr.puts "Usage: llmemory edges USER_ID [--subject NODE_ID] [--limit N]"
              exit 1
            end

            storage = graph_based_storage(@store_type)
            edges = storage.list_edges(user_id, subject_id: @subject_id, limit: @limit)

            if edges.empty?
              puts "No edges found for user #{user_id}."
              return
            end

            edges.each do |e|
              id = e.respond_to?(:id) ? e.id : e[:id]
              subj = e.respond_to?(:subject_id) ? e.subject_id : e[:subject_id]
              pred = e.respond_to?(:predicate) ? e.predicate : e[:predicate]
              obj = e.respond_to?(:target_id) ? e.target_id : e[:object_id]
              puts "#{id}: #{subj} --#{pred}--> #{obj}"
            end
          end
        end
      end
    end
  end
end
