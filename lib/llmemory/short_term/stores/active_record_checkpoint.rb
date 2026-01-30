# frozen_string_literal: true

# Model for short-term checkpoint (ActiveRecordStore). Table: llmemory_checkpoints.
# Create with: rails g llmemory:install && rails db:migrate

module Llmemory
  module ShortTerm
    module Stores
      class ActiveRecordCheckpoint < ::ActiveRecord::Base
        self.table_name = "llmemory_checkpoints"
      end
    end
  end
end
