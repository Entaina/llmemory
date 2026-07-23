# frozen_string_literal: true

require "time"
require_relative "short_term/stores"

module Llmemory
  # Append-only audit trail of forgotten memory entries. CoALA notes that
  # modifying and deleting memory ("unlearning") are understudied; when an agent
  # removes knowledge it should remain accountable for what was removed, when and
  # why. ForgetLog records that trail, unified per user across memory types.
  #
  # Backed by the same pluggable short-term stores as the rest of the session
  # layer, under a per-user pseudo-session key.
  class ForgetLog
    SESSION_KEY = "__forget_log__"

    def initialize(store: nil)
      @store = store || ShortTerm::Stores.build
    end

    def record(user_id, memory_type:, ids:, reason: nil)
      ids = Array(ids).map(&:to_s)
      entry = {
        memory_type: memory_type.to_s,
        ids: ids,
        count: ids.size,
        reason: reason,
        at: Time.now.iso8601
      }
      @store.update(user_id, SESSION_KEY) do |state|
        state = symbolize(state || {})
        log = state[:entries]
        log = log.is_a?(Array) ? log.map { |e| symbolize(e) } : []
        log << entry
        state.merge(entries: log)
      end
      entry
    end

    def entries(user_id)
      state = @store.load(user_id, SESSION_KEY)
      return [] unless state.is_a?(Hash)
      list = state[:entries] || state["entries"]
      list.is_a?(Array) ? list.map { |e| symbolize(e) } : []
    end

    private

    def symbolize(entry)
      return entry unless entry.is_a?(Hash)
      entry.each_with_object({}) { |(k, v), acc| acc[k.to_sym] = v }
    end
  end
end
