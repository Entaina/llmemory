# frozen_string_literal: true

require_relative "base"

module Llmemory
  module Cli
    module Commands
      class Stats < Base
        def option_parser(parser)
          parser.on("--store TYPE", "Store type") { |v| @store_type = v }
        end

        def execute(argv, _opts)
          user_id = argv.first
          short_store = short_term_store(@store_type)
          long_type = Llmemory.configuration.long_term_type.to_s

          if user_id
            print_user_stats(user_id, short_store, long_type)
          else
            print_global_stats(short_store, long_type)
          end
        end

        private

        def print_user_stats(user_id, short_store, long_type)
          puts "Stats for user: #{user_id}"
          puts "---"

          sessions = short_store.list_sessions(user_id: user_id)
          puts "Short-term sessions: #{sessions.size}"

          if long_type == "graph_based"
            storage = graph_based_storage(@store_type)
            puts "Long-term (graph) nodes: #{storage.count_nodes(user_id)}"
            puts "Long-term (graph) edges: #{storage.count_edges(user_id)}"
          else
            storage = file_based_storage(@store_type)
            puts "Long-term (file) items: #{storage.count_items(user_id: user_id)}"
            puts "Long-term (file) categories: #{storage.list_categories(user_id).size}"
            puts "Long-term (file) resources: #{storage.list_resources(user_id: user_id).size}"
          end
        end

        def print_global_stats(short_store, long_type)
          users = short_store.list_users
          puts "Total users (short-term): #{users.size}"
          puts "---"

          if long_type == "graph_based"
            storage = graph_based_storage(@store_type)
            long_users = storage.list_users
            puts "Total users (long-term graph): #{long_users.size}"
            total_nodes = long_users.sum { |u| storage.count_nodes(u) }
            total_edges = long_users.sum { |u| storage.count_edges(u) }
            puts "Total nodes: #{total_nodes}"
            puts "Total edges: #{total_edges}"
          else
            storage = file_based_storage(@store_type)
            long_users = storage.list_users
            puts "Total users (long-term file): #{long_users.size}"
            total_items = long_users.sum { |u| storage.count_items(user_id: u) }
            puts "Total items: #{total_items}"
          end
        end
      end
    end
  end
end
