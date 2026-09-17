# frozen_string_literal: true

module LocalBenchmark
  module Canonical
    module_function

    def validate!(conversation)
      raise ArgumentError, "conversation id required" if conversation["id"].to_s.empty?
      raise ArgumentError, "sessions required" unless conversation["sessions"].is_a?(Array)
      raise ArgumentError, "queries required" unless conversation["queries"].is_a?(Array)
    end

    def limit_conversations(conversations, limit:)
      return conversations if limit.nil? || limit.to_i <= 0

      remaining = limit.to_i
      out = []
      conversations.each do |conv|
        break if remaining <= 0

        queries = Array(conv["queries"])
        if queries.size <= remaining
          out << conv
          remaining -= queries.size
        else
          dup = conv.dup
          dup["queries"] = queries.first(remaining)
          out << dup
          remaining = 0
        end
      end
      out
    end
  end
end
