# frozen_string_literal: true

module Llmemory
  module ShortTerm
    module Stores
      class Base
        def save(user_id, session_id, state)
          raise NotImplementedError, "#{self.class}#save must be implemented"
        end

        def load(user_id, session_id)
          raise NotImplementedError, "#{self.class}#load must be implemented"
        end

        def delete(user_id, session_id)
          raise NotImplementedError, "#{self.class}#delete must be implemented"
        end

        # Atomic read-modify-write. Yields the current state (may be nil) and
        # persists the block's return value when non-nil.
        def update(user_id, session_id)
          current = load(user_id, session_id)
          new_state = yield(current)
          save(user_id, session_id, new_state) unless new_state.nil?
          new_state
        end

        def list_users
          raise NotImplementedError, "#{self.class}#list_users must be implemented"
        end

        def list_sessions(user_id:)
          raise NotImplementedError, "#{self.class}#list_sessions must be implemented"
        end
      end
    end
  end
end
