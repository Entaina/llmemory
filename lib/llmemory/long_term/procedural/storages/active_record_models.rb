# frozen_string_literal: true

# Model for Procedural ActiveRecordStorage. Loaded only when using
# store: :active_record. JSONB `data` auto-deserializes to a Hash in Rails 5+.

module Llmemory
  module LongTerm
    module Procedural
      module Storages
        class LlmemorySkill < ::ActiveRecord::Base
          self.table_name = "llmemory_skills"
          self.primary_key = "id"
        end
      end
    end
  end
end
