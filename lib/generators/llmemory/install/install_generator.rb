# frozen_string_literal: true

require "rails/generators/migration"

module Llmemory
  module Generators
    class InstallGenerator < ::Rails::Generators::Base
      include Rails::Generators::Migration

      source_root File.expand_path("templates", __dir__)

      desc "Create migration for llmemory long-term storage (ActiveRecord)"

      def self.next_migration_number(dirname)
        next_migration_number = current_migration_number(dirname) + 1
        ActiveRecord::Migration.next_migration_number(next_migration_number)
      end

      def copy_migration
        migration_template "create_llmemory_tables.rb", "db/migrate/create_llmemory_tables.rb"
      end
    end
  end
end
