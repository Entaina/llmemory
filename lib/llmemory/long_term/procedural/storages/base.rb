# frozen_string_literal: true

module Llmemory
  module LongTerm
    module Procedural
      module Storages
        # Storage contract for procedural memory (skill library). Implementations
        # persist Skill hashes, support keyword search and name lookup (for
        # versioning), and record success/failure outcomes.
        class Base
          def save_skill(user_id, skill)
            raise NotImplementedError, "#{self.class}#save_skill must be implemented"
          end

          def get_skill(user_id, id)
            raise NotImplementedError, "#{self.class}#get_skill must be implemented"
          end

          def list_skills(user_id, limit: nil)
            raise NotImplementedError, "#{self.class}#list_skills must be implemented"
          end

          def search_skills(user_id, query)
            raise NotImplementedError, "#{self.class}#search_skills must be implemented"
          end

          def find_skills_by_name(user_id, name)
            raise NotImplementedError, "#{self.class}#find_skills_by_name must be implemented"
          end

          # Increments the success or failure count of a skill and returns the
          # updated skill hash (or nil if not found).
          def record_outcome(user_id, skill_id, success:)
            raise NotImplementedError, "#{self.class}#record_outcome must be implemented"
          end

          def count_skills(user_id)
            raise NotImplementedError, "#{self.class}#count_skills must be implemented"
          end

          # Deletes skills by id. Returns the number actually removed.
          def delete_skills(user_id, ids)
            raise NotImplementedError, "#{self.class}#delete_skills must be implemented"
          end

          def list_users
            raise NotImplementedError, "#{self.class}#list_users must be implemented"
          end
        end
      end
    end
  end
end
