# frozen_string_literal: true

require_relative "../canonical"

module LocalBenchmark
  module Adapters
    class Base
      def available?
        false
      end

      def skip_reason
        "dataset not configured"
      end

      def each_conversation
        return enum_for(:each_conversation) unless block_given?
        return unless available?

        raise NotImplementedError
      end

      def conversations(limit: nil)
        list = each_conversation.to_a
        list.each { |c| Canonical.validate!(c) }
        Canonical.limit_conversations(list, limit: limit)
      end
    end
  end
end
