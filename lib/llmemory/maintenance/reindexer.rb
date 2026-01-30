# frozen_string_literal: true

module Llmemory
  module Maintenance
    class Reindexer
      ARCHIVE_AFTER_DAYS = 180

      def initialize(storage)
        @storage = storage
      end

      def run_monthly(user_id)
        items = @storage.get_all_items(user_id)
        resources = @storage.get_all_resources(user_id)
        cutoff = Time.now - (ARCHIVE_AFTER_DAYS * 86400)

        old_item_ids = items.select { |i| i[:created_at] < cutoff }.map { |i| i[:id] }
        old_resource_ids = resources.select { |r| r[:created_at] < cutoff }.map { |r| r[:id] }

        @storage.archive_items(user_id, old_item_ids) if old_item_ids.any?
        @storage.archive_resources(user_id, old_resource_ids) if old_resource_ids.any?

        true
      end
    end
  end
end
