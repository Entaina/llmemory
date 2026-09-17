# frozen_string_literal: true

module ZeroMemBenchmark
  module Adapters
    # Protocol for optional external benchmarks (never required in CI).
    class ExternalDataset
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
    end
  end
end
