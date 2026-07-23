# frozen_string_literal: true

require_relative "short_term/stores"

module Llmemory
  # CoALA's "working memory": a structured, symbolic scratch space that persists
  # across LLM calls within a session — distinct from the raw message buffer
  # (Checkpoint). It is the central hub an agent reads from and writes to while
  # reasoning (goals, current task, retrieved context, intermediate reasoning,
  # last observation, free-form scratchpad), plus arbitrary custom slots.
  #
  # Backed by the same pluggable short-term stores as Checkpoint, but under a
  # namespaced session key so working-memory slots never collide with messages.
  class WorkingMemory
    DEFAULT_SESSION_ID = "default"
    SESSION_SUFFIX = ":working_memory"
    SLOTS = %i[goals current_task retrieved_context scratchpad last_observation intermediate_reasoning].freeze

    attr_reader :user_id, :session_id

    def initialize(user_id:, session_id: DEFAULT_SESSION_ID, store: nil)
      @user_id = user_id
      @session_id = session_id
      @store_key = "#{session_id}#{SESSION_SUFFIX}"
      @store = store || ShortTerm::Stores.build
    end

    SLOTS.each do |slot|
      define_method(slot) { read[slot] }
      define_method("#{slot}=") { |value| set(slot, value) }
    end

    # Read/write an arbitrary slot (typed or custom).
    def get(slot)
      read[slot.to_sym]
    end

    def set(slot, value)
      @store.update(@user_id, @store_key) do |state|
        state = symbolize(state || {})
        state[slot.to_sym] = value
        state
      end
      value
    end

    # Bulk update in a single write.
    def update(**slots)
      @store.update(@user_id, @store_key) do |state|
        state = symbolize(state || {})
        slots.each { |k, v| state[k.to_sym] = v }
        state
      end
    end

    # Slots set by the caller beyond the predefined typed ones.
    def custom_slots
      read.reject { |k, _| SLOTS.include?(k) }
    end

    def to_h
      read
    end

    def clear!
      @store.delete(@user_id, @store_key)
      true
    end

    private

    def read
      state = @store.load(@user_id, @store_key)
      return {} unless state.is_a?(Hash)
      symbolize(state)
    end

    def persist(state)
      @store.save(@user_id, @store_key, state)
    end

    def symbolize(hash)
      hash.each_with_object({}) { |(k, v), acc| acc[k.to_sym] = v }
    end
  end
end
