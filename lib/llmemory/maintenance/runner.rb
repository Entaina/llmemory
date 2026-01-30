# frozen_string_literal: true

require_relative "consolidator"
require_relative "summarizer"
require_relative "reindexer"

module Llmemory
  module Maintenance
    class Runner
      class << self
        def run_nightly(user_id, storage: nil)
          storage ||= default_storage(user_id)
          Consolidator.new(storage).run_nightly(user_id)
        end

        def run_weekly(user_id, storage: nil)
          storage ||= default_storage(user_id)
          Summarizer.new(storage).run_weekly(user_id)
        end

        def run_monthly(user_id, storage: nil)
          storage ||= default_storage(user_id)
          Reindexer.new(storage).run_monthly(user_id)
        end

        private

        def default_storage(user_id)
          Llmemory::LongTerm::FileBased::Storages.build
        end
      end
    end
  end
end
