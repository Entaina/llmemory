# frozen_string_literal: true

module Llmemory
  module ShortTerm
    class SessionLifecycle
      def initialize(store: nil)
        @store = store || build_store
      end

      def cleanup_idle_sessions!(user_id:, idle_minutes: nil)
        idle_minutes ||= Llmemory.configuration.session_idle_minutes
        cutoff = Time.now - (idle_minutes * 60)
        deleted = 0

        @store.list_sessions(user_id: user_id).each do |session_id|
          state = @store.load(user_id, session_id)
          next unless state.is_a?(Hash)

          last_activity = state[:last_activity_at] || state["last_activity_at"]
          next if last_activity.nil?

          last_time = last_activity.is_a?(Time) ? last_activity : Time.parse(last_activity.to_s)
          if last_time < cutoff
            @store.delete(user_id, session_id)
            deleted += 1
          end
        end

        deleted
      end

      def cleanup_stale_sessions!(user_id:, prune_after_days: nil)
        prune_after_days ||= Llmemory.configuration.session_prune_after_days
        cutoff = Time.now - (prune_after_days * 86400)
        deleted = 0

        @store.list_sessions(user_id: user_id).each do |session_id|
          state = @store.load(user_id, session_id)
          next unless state.is_a?(Hash)

          last_activity = state[:last_activity_at] || state["last_activity_at"]
          next if last_activity.nil?

          last_time = last_activity.is_a?(Time) ? last_activity : Time.parse(last_activity.to_s)
          if last_time < cutoff
            @store.delete(user_id, session_id)
            deleted += 1
          end
        end

        deleted
      end

      def enforce_max_entries!(user_id:, max_entries: nil)
        max_entries ||= Llmemory.configuration.session_max_entries_per_user
        sessions = @store.list_sessions(user_id: user_id)
        return 0 if sessions.size <= max_entries

        session_ages = sessions.map do |session_id|
          state = @store.load(user_id, session_id)
          last_activity = state&.dig(:last_activity_at) || state&.dig("last_activity_at")
          last_time = last_activity.is_a?(Time) ? last_activity : (last_activity ? Time.parse(last_activity.to_s) : Time.at(0))
          [session_id, last_time]
        end

        session_ages.sort_by! { |_, t| t }
        to_delete = session_ages.first(session_ages.size - max_entries).map(&:first)
        to_delete.each { |sid| @store.delete(user_id, sid) }
        to_delete.size
      end

      private

      def build_store
        case Llmemory.configuration.short_term_store.to_sym
        when :memory then Stores::MemoryStore.new
        when :redis then Stores::RedisStore.new
        when :postgres then Stores::PostgresStore.new
        when :active_record, :activerecord
          require_relative "stores/active_record_store"
          Stores::ActiveRecordStore.new
        else
          Stores::MemoryStore.new
        end
      end
    end
  end
end
