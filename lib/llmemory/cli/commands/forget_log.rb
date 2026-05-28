# frozen_string_literal: true

require_relative "base"

module Llmemory
  module Cli
    module Commands
      class ForgetLog < Commands::Base
        def execute(argv, _opts)
          user_id = argv.first
          unless user_id
            $stderr.puts "Usage: llmemory forget-log USER_ID"
            exit 1
          end

          entries = Llmemory::ForgetLog.new(store: short_term_store).entries(user_id)

          if entries.empty?
            puts "No forget audit entries for user #{user_id}."
            return
          end

          entries.each do |e|
            type = e[:memory_type] || e["memory_type"]
            count = e[:count] || e["count"]
            reason = e[:reason] || e["reason"]
            at = e[:at] || e["at"]
            ids = e[:ids] || e["ids"] || []
            reason_str = reason ? " — #{reason}" : ""
            puts "[#{at}] #{type}: removed #{count} (#{ids.join(', ')})#{reason_str}"
          end
        end
      end
    end
  end
end
