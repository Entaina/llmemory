# frozen_string_literal: true

module Llmemory
  module LongTerm
    module Episodic
      module Storages
        # Storage contract for episodic memory. Implementations persist Episode
        # hashes and expose recency-ordered listing plus keyword search so the
        # retrieval Engine can rank episodes alongside other memory types.
        class Base
          def save_episode(user_id, episode)
            raise NotImplementedError, "#{self.class}#save_episode must be implemented"
          end

          def get_episode(user_id, id)
            raise NotImplementedError, "#{self.class}#get_episode must be implemented"
          end

          # Newest first. Optionally capped by limit.
          def list_episodes(user_id, limit: nil)
            raise NotImplementedError, "#{self.class}#list_episodes must be implemented"
          end

          def search_episodes(user_id, query)
            raise NotImplementedError, "#{self.class}#search_episodes must be implemented"
          end

          def count_episodes(user_id)
            raise NotImplementedError, "#{self.class}#count_episodes must be implemented"
          end

          def list_users
            raise NotImplementedError, "#{self.class}#list_users must be implemented"
          end
        end
      end
    end
  end
end
