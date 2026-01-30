# frozen_string_literal: true

# Models for ActiveRecordStorage. Loaded only when using store: :active_record.
# In Rails, run: rails g llmemory:install (or create the migration manually).

module Llmemory
  module LongTerm
    module FileBased
      module Storages
        class LlmemoryResource < ::ActiveRecord::Base
          self.table_name = "llmemory_resources"
          self.primary_key = "id"
        end

        class LlmemoryItem < ::ActiveRecord::Base
          self.table_name = "llmemory_items"
          self.primary_key = "id"
        end

        class LlmemoryCategory < ::ActiveRecord::Base
          self.table_name = "llmemory_categories"
        end
      end
    end
  end
end
