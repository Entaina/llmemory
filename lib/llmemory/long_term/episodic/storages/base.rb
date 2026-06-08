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

          # Newest first. Optionally paginated with offset/limit.
          def list_episodes(user_id, limit: nil, offset: nil)
            raise NotImplementedError, "#{self.class}#list_episodes must be implemented"
          end

          def search_episodes(user_id, query)
            raise NotImplementedError, "#{self.class}#search_episodes must be implemented"
          end

          def count_episodes(user_id)
            raise NotImplementedError, "#{self.class}#count_episodes must be implemented"
          end

          # Deletes episodes by id. Returns the number actually removed.
          def delete_episodes(user_id, ids)
            raise NotImplementedError, "#{self.class}#delete_episodes must be implemented"
          end

          # Soft-archives episodes by id (sets archived_at on the record). Archived
          # episodes are excluded from list_episodes / search_episodes / count_episodes
          # but remain accessible via get_episode. Returns the number archived.
          def archive_episodes(user_id, ids)
            raise NotImplementedError, "#{self.class}#archive_episodes must be implemented"
          end

          # Returns episodes whose created_at is older than the cutoff and that are
          # not already archived. Used by the TTL maintenance job.
          def expired_episode_ids(user_id, cutoff:)
            raise NotImplementedError, "#{self.class}#expired_episode_ids must be implemented"
          end

          def list_users
            raise NotImplementedError, "#{self.class}#list_users must be implemented"
          end
        end
      end
    end
  end
end
