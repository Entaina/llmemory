# frozen_string_literal: true

require "rails/generators"

module Llmemory
  module Generators
    class UpgradeZeroMemGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Add Zero-Mem trace tables (llmemory_traces, state links, reserved index tables)"

      def copy_migration
        timestamp = Time.now.utc.strftime("%Y%m%d%H%M%S")
        template "create_llmemory_zero_mem_tables.rb",
                 "db/migrate/#{timestamp}_create_llmemory_zero_mem_tables.rb"
      end
    end
  end
end
