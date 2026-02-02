# frozen_string_literal: true

require_relative "base"

module Llmemory
  module Cli
    module Commands
      class Users < Base
        def option_parser(parser)
          parser.on("--store TYPE", "Short-term store: memory, redis, postgres, active_record") do |v|
            @store_type = v
          end
        end

        def execute(_argv, _opts)
          store = short_term_store(@store_type)
          users = store.list_users
          if users.empty?
            puts "No users with short-term memory found."
          else
            users.each { |u| puts u }
          end
        end
      end
    end
  end
end
