# frozen_string_literal: true

require "json"
require_relative "../base"

module Llmemory
  module Cli
    module Commands
      module LongTerm
        class Graph < Commands::Base
          def option_parser(parser)
            parser.on("--format FORMAT", "Output format: dot, json") { |v| @format = (v || "dot").downcase }
            parser.on("--store TYPE", "Storage type") { |v| @store_type = v }
          end

          def execute(argv, _opts)
            user_id = argv.first
            unless user_id
              $stderr.puts "Usage: llmemory graph USER_ID [--format dot|json]"
              exit 1
            end

            storage = graph_based_storage(@store_type)
            nodes = storage.list_nodes(user_id)
            edges = storage.list_edges(user_id)

            case @format
            when "json"
              puts JSON.pretty_generate(
                nodes: nodes.map { |n| node_to_h(n) },
                edges: edges.map { |e| edge_to_h(e) }
              )
            else
              puts to_dot(nodes, edges)
            end
          end

          private

          def node_to_h(n)
            if n.respond_to?(:to_h)
              n.to_h
            else
              { id: n[:id], entity_type: n[:entity_type], name: n[:name] }
            end
          end

          def edge_to_h(e)
            if e.respond_to?(:to_h)
              e.to_h
            else
              { id: e[:id], subject_id: e[:subject_id], predicate: e[:predicate], object_id: e[:object_id] }
            end
          end

          def to_dot(nodes, edges)
            lines = ["digraph llmemory {"]
            nodes.each do |n|
              id = n.respond_to?(:id) ? n.id : n[:id]
              name = (n.respond_to?(:name) ? n.name : n[:name]).to_s.gsub('"', '\\"')
              lines << "  \"#{id}\" [label=\"#{name}\"];"
            end
            edges.each do |e|
              subj = e.respond_to?(:subject_id) ? e.subject_id : e[:subject_id]
              obj = e.respond_to?(:object_id) ? e.object_id : e[:object_id]
              pred = e.respond_to?(:predicate) ? e.predicate : e[:predicate]
              lines << "  \"#{subj}\" -> \"#{obj}\" [label=\"#{pred}\"];"
            end
            lines << "}"
            lines.join("\n")
          end
        end
      end
    end
  end
end
