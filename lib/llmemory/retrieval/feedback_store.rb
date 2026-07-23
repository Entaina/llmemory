# frozen_string_literal: true

require_relative "../short_term/stores"

module Llmemory
  module Retrieval
    # Persists retrieval feedback: a net utility signal per (user, memory item),
    # accumulated from agents marking retrieved items useful (+1) or harmful (-1).
    #
    # CoALA flags adaptive retrieval — "learning better retrieval procedures" — as
    # understudied. This is the minimal substrate for it: a feedback ledger the
    # Engine consults to boost repeatedly-useful items and dampen noise.
    #
    # Backed by the same pluggable short-term stores as Checkpoint/WorkingMemory,
    # under a per-user pseudo-session key.
    class FeedbackStore
      SESSION_KEY = "__retrieval_feedback__"

      def initialize(store: nil)
        @store = store || ShortTerm::Stores.build
      end

      def record(user_id, item_id, delta)
        return if user_id.nil? || item_id.nil?

        key = item_id.to_s
        state = @store.update(user_id, SESSION_KEY) do |current|
          current = load_from_state(current)
          current[key] = (current[key] || 0) + delta.to_i
          current
        end
        state ? state[key] : nil
      end

      def net(user_id, item_id)
        return 0 if user_id.nil? || item_id.nil?
        load(user_id)[item_id.to_s] || 0
      end

      def all(user_id)
        load(user_id)
      end

      private

      def load(user_id)
        load_from_state(@store.load(user_id, SESSION_KEY))
      end

      def load_from_state(state)
        return {} unless state.is_a?(Hash)
        state.each_with_object({}) { |(k, v), acc| acc[k.to_s] = v.to_i }
      end
    end
  end
end
