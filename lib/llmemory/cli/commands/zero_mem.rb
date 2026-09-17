# frozen_string_literal: true

require "json"
require_relative "base"

module Llmemory
  module Cli
    module Commands
      class ZeroMem < Base
        def option_parser(parser)
          parser.on("--session SESSION", "Session id (default: default)") { |v| @session_id = v }
          parser.on("--explain", "Include explain payload on search") { @explain = true }
        end

        def execute(argv, _opts)
          sub = argv.shift
          case sub
          when "traces"
            run_traces(argv)
          when "reindex"
            run_reindex(argv)
          when "status"
            run_status(argv)
          when "search"
            run_search(argv)
          else
            print_usage
            exit 1
          end
        end

        private

        def print_usage
          $stderr.puts <<~HELP
            Usage:
              llmemory zero-mem traces USER_ID [--session SESSION]
              llmemory zero-mem reindex USER_ID [--session SESSION]
              llmemory zero-mem status USER_ID [--session SESSION]
              llmemory zero-mem search USER_ID "query" [--explain]
          HELP
        end

        def build_memory(user_id)
          trace_store = Llmemory::ZeroMem::Storages.build
          Llmemory::Memory.new(
            user_id: user_id,
            session_id: @session_id || "default",
            trace_store: trace_store,
            memory_mode: :zero_mem
          )
        end

        def run_traces(argv)
          user_id = argv.shift
          unless user_id
            print_usage
            exit 1
          end

          memory = build_memory(user_id)
          traces = memory.trace_store.list_traces(user_id, session_id: @session_id || "default")
          traces.each do |t|
            puts "[#{t.id}] seq=#{t.sequence} #{t.role}: #{t.content[0, 120]}"
          end
        end

        def run_reindex(argv)
          user_id = argv.shift
          unless user_id
            print_usage
            exit 1
          end

          memory = build_memory(user_id)
          status = memory.reindex_traces!(session_id: @session_id || "default")
          puts JSON.generate(status)
        end

        def run_status(argv)
          user_id = argv.shift
          unless user_id
            print_usage
            exit 1
          end

          memory = build_memory(user_id)
          puts JSON.generate(memory.zero_mem_status(session_id: @session_id || "default"))
        end

        def run_search(argv)
          user_id = argv.shift
          query = argv.join(" ").strip
          unless user_id && !query.empty?
            print_usage
            exit 1
          end

          memory = build_memory(user_id)
          result = memory.retrieve_evidence(query, explain: @explain == true)
          puts result.to_context
          puts JSON.generate(metrics: result.metrics, route: result.route) if @explain
        end
      end
    end
  end
end
