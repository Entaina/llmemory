# frozen_string_literal: true

module Llmemory
  module Maintenance
    # TTL expiry job: soft-archives episodic/procedural entries whose age
    # exceeds the configured per-type TTL. Designed to run as a maintenance
    # task (cron / Rails Job). Idempotent — already-archived entries are
    # skipped by the storage layer.
    #
    # Reads `Llmemory.configuration.ttl_episodic_days` and
    # `Llmemory.configuration.ttl_procedural_days`. A nil/zero TTL disables
    # expiry for that memory type.
    #
    # Returns a hash `{ episodic: N, procedural: M }` with the number of
    # entries archived per type for the given user.
    class TTLExpiry
      DEFAULT_REASON = "ttl_expired"

      def self.run!(user_id, episodic: nil, procedural: nil, reason: DEFAULT_REASON)
        new(user_id, episodic: episodic, procedural: procedural, reason: reason).run!
      end

      def initialize(user_id, episodic: nil, procedural: nil, reason: DEFAULT_REASON)
        @user_id = user_id
        @episodic = episodic
        @procedural = procedural
        @reason = reason
      end

      def run!
        {
          episodic: expire(memory: @episodic ||= Llmemory::LongTerm::Episodic::Memory.new(user_id: @user_id),
                           ttl_days: Llmemory.configuration.ttl_episodic_days),
          procedural: expire(memory: @procedural ||= Llmemory::LongTerm::Procedural::Memory.new(user_id: @user_id),
                             ttl_days: Llmemory.configuration.ttl_procedural_days)
        }
      end

      private

      def expire(memory:, ttl_days:)
        return 0 unless ttl_days && ttl_days.to_f.positive?
        cutoff = Time.now - (ttl_days.to_f * 86400)
        ids = memory.expired_ids(cutoff: cutoff)
        return 0 if ids.empty?
        memory.forget(ids: ids, reason: @reason, mode: :soft)
      end
    end
  end
end
