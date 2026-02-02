# frozen_string_literal: true

require_relative "base"

module Llmemory
  module Cli
    module Commands
      class Search < Base
        def option_parser(parser)
          parser.on("--type TYPE", "Search in: short, long, all (default: all)") { |v| @search_type = (v || "all").downcase }
          parser.on("--store TYPE", "Store type") { |v| @store_type = v }
        end

        def execute(argv, _opts)
          user_id = argv.shift
          query = argv.join(" ").strip
          unless user_id && !query.empty?
            $stderr.puts "Usage: llmemory search USER_ID \"query\" [--type short|long|all]"
            exit 1
          end

          type = @search_type || "all"

          if type == "short" || type == "all"
            search_short_term(user_id, query)
          end

          if type == "long" || type == "all"
            if Llmemory.configuration.long_term_type.to_s == "graph_based"
              search_graph_based(user_id, query)
            else
              search_file_based(user_id, query)
            end
          end
        end

        private

        def search_short_term(user_id, query)
          store = short_term_store(@store_type)
          sessions = store.list_sessions(user_id: user_id)
          puts "=== Short-term ==="
          sessions.each do |session_id|
            state = store.load(user_id, session_id)
            next unless state
            messages = state[:messages] || state["messages"] || []
            messages.each do |m|
              content = (m[:content] || m["content"]).to_s
              next unless content.downcase.include?(query.downcase)
              role = m[:role] || m["role"]
              puts "[#{session_id}] [#{role}] #{content[0, 150]}..."
            end
          end
        end

        def search_file_based(user_id, query)
          storage = file_based_storage(@store_type)
          puts "=== Long-term (file-based) ==="
          items = storage.search_items(user_id, query)
          items.each do |i|
            content = (i[:content] || i["content"]).to_s
            puts "[#{i[:category]}] #{content}"
          end
          resources = storage.search_resources(user_id, query)
          resources.each do |r|
            text = (r[:text] || r["text"]).to_s
            puts "[resource] #{text[0, 150]}..."
          end
        end

        def search_graph_based(user_id, query)
          storage = graph_based_storage(@store_type)
          puts "=== Long-term (graph-based) ==="
          nodes = storage.list_nodes(user_id)
          query_lower = query.downcase
          nodes.each do |n|
            name = (n.respond_to?(:name) ? n.name : n[:name]).to_s
            next unless name.downcase.include?(query_lower)
            type = n.respond_to?(:entity_type) ? n.entity_type : n[:entity_type]
            puts "[node] #{type}: #{name}"
          end
        end
      end
    end
  end
end
