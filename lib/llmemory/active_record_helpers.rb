# frozen_string_literal: true

module Llmemory
  module ActiveRecordHelpers
    UNIQUE_RETRY_LIMIT = 3

    private

    def with_unique_retry(limit: UNIQUE_RETRY_LIMIT)
      attempts = 0
      begin
        yield
      rescue ActiveRecord::RecordNotUnique
        attempts += 1
        raise if attempts >= limit

        retry
      end
    end
  end
end
