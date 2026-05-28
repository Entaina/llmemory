# frozen_string_literal: true

# Model for Episodic ActiveRecordStorage. Loaded only when using
# store: :active_record. JSONB `data` auto-deserializes to a Hash in Rails 5+.

module Llmemory
  module LongTerm
    module Episodic
      module Storages
        class LlmemoryEpisode < ::ActiveRecord::Base
          self.table_name = "llmemory_episodes"
          self.primary_key = "id"
        end
      end
    end
  end
end
