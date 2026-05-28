# frozen_string_literal: true

require_relative "base"

module Llmemory
  module Cli
    module Commands
      class Working < Commands::Base
        def execute(argv, _opts)
          user_id, session_id = argv
          unless user_id && session_id
            $stderr.puts "Usage: llmemory working USER_ID SESSION_ID"
            exit 1
          end

          wm = Llmemory::WorkingMemory.new(user_id: user_id, session_id: session_id, store: short_term_store)
          state = wm.to_h

          if state.empty?
            puts "Empty working memory for user #{user_id}, session #{session_id}."
            return
          end

          state.each do |slot, value|
            puts "#{slot}: #{value.inspect}"
          end
        end
      end
    end
  end
end
