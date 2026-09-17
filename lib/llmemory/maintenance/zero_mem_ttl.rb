# frozen_string_literal: true

module Llmemory
  module Maintenance
    class ZeroMemTTL
      def initialize(storage:, ttl_days: nil)
        @storage = storage
        @ttl_days = ttl_days || Llmemory.configuration.zero_mem_ttl_days
      end

      def run!(user_id:, dry_run: false)
        return { archived: 0, skipped: true } if @ttl_days.nil? || @ttl_days.to_i <= 0

        cutoff = Time.now - (@ttl_days.to_i * 86_400)
        archived = 0
        @storage.list_traces(user_id, include_archived: false).each do |trace|
          next unless trace.occurred_at < cutoff

          archived += 1
          @storage.archive_trace(user_id, trace.id) unless dry_run
        end
        { archived: archived, dry_run: dry_run, cutoff: cutoff.utc.iso8601 }
      end
    end
  end
end
