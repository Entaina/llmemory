# frozen_string_literal: true

require_relative "stores"

module Llmemory
  module ShortTerm
    class Checkpoint
      DEFAULT_SESSION_ID = "default"

      def initialize(user_id:, session_id: DEFAULT_SESSION_ID, store: nil)
        @user_id = user_id
        @session_id = session_id
        @store = store || build_store
      end

      def save_state(state)
        @store.save(@user_id, @session_id, state)
      end

      def restore_state
        @store.load(@user_id, @session_id)
      end

      def clear_state
        @store.delete(@user_id, @session_id)
      end

      private

      def build_store
        Stores.build
      end
    end
  end
end
