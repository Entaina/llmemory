# frozen_string_literal: true

require_relative "base"

module Llmemory
  module Cli
    module Commands
      class ShortTerm < Base
        DEFAULT_SESSION = "default"

        def option_parser(parser)
          parser.on("--session SESSION_ID", "Session ID (default: default)") { |v| @session_id = v }
          parser.on("--list-sessions", "List sessions for the user") { @list_sessions = true }
          parser.on("--store TYPE", "Store type") { |v| @store_type = v }
        end

        def execute(argv, _opts)
          user_id = argv.first
          unless user_id
            $stderr.puts "Usage: llmemory short-term USER_ID [--session SESSION_ID] [--list-sessions]"
            exit 1
          end

          store = short_term_store(@store_type)

          if @list_sessions
            sessions = store.list_sessions(user_id: user_id)
            if sessions.empty?
              puts "No sessions found for user #{user_id}."
            else
              sessions.each { |s| puts s }
            end
            return
          end

          session_id = @session_id || DEFAULT_SESSION
          state = store.load(user_id, session_id)
          if state.nil?
            puts "No state found for user #{user_id}, session #{session_id}."
            return
          end

          messages = state[:messages] || state["messages"] || []
          if messages.empty?
            puts "No messages in session #{session_id}."
            return
          end

          messages.each do |m|
            role = m[:role] || m["role"]
            content = (m[:content] || m["content"]).to_s
            content = content[0, 200] + "..." if content.length > 200
            puts "[#{role}] #{content}"
          end
        end
      end
    end
  end
end
