# frozen_string_literal: true

require_relative "stores"

module Llmemory
  module ShortTerm
    class SessionLifecycle
      # Pseudo-sessions used by ForgetLog, FeedbackStore and WorkingMemory share
      # the short-term K/V store but are not user sessions — they must not be
      # idle-pruned, stale-pruned, or evicted by enforce_max_entries.
      PSEUDO_SESSION_PATTERNS = [
        /\A__[a-z_]+__\z/,    # e.g. "__forget_log__", "__retrieval_feedback__"
        /:working_memory\z/    # WorkingMemory uses "<session>:working_memory"
      ].freeze

      def self.pseudo_session?(session_id)
        PSEUDO_SESSION_PATTERNS.any? { |p| session_id.to_s.match?(p) }
      end

      def initialize(store: nil)
        @store = store || build_store
      end

      def cleanup_idle_sessions!(user_id:, idle_minutes: nil)
        idle_minutes ||= Llmemory.configuration.session_idle_minutes
        cutoff = Time.now - (idle_minutes * 60)
        deleted = 0

        user_sessions(user_id).each do |session_id|
          state = @store.load(user_id, session_id)
          next unless state.is_a?(Hash)

          last_time = parse_activity_time(state)
          next if last_time.nil?

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

        user_sessions(user_id).each do |session_id|
          state = @store.load(user_id, session_id)
          next unless state.is_a?(Hash)

          last_time = parse_activity_time(state)
          next if last_time.nil?

          if last_time < cutoff
            @store.delete(user_id, session_id)
            deleted += 1
          end
        end

        deleted
      end

      def enforce_max_entries!(user_id:, max_entries: nil)
        max_entries ||= Llmemory.configuration.session_max_entries_per_user
        sessions = user_sessions(user_id)
        return 0 if sessions.size <= max_entries

        session_ages = sessions.filter_map do |session_id|
          state = @store.load(user_id, session_id)
          last_time = parse_activity_time(state) || Time.at(0)
          [session_id, last_time]
        end

        session_ages.sort_by! { |_, t| t }
        to_delete = session_ages.first(session_ages.size - max_entries).map(&:first)
        to_delete.each { |sid| @store.delete(user_id, sid) }
        to_delete.size
      end

      private

      def user_sessions(user_id)
        @store.list_sessions(user_id: user_id).reject { |s| self.class.pseudo_session?(s) }
      end

      def parse_activity_time(state)
        return nil unless state.is_a?(Hash)

        last_activity = state[:last_activity_at] || state["last_activity_at"]
        return nil if last_activity.nil?
        return last_activity if last_activity.is_a?(Time)

        Time.parse(last_activity.to_s)
      rescue ArgumentError, TypeError
        nil
      end

      def build_store
        Stores.build
      end
    end
  end
end
