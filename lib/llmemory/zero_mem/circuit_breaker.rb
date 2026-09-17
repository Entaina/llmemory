# frozen_string_literal: true

module Llmemory
  module ZeroMem
    class CircuitBreaker
      def initialize(failure_threshold: 3, cool_down_seconds: 30)
        @failure_threshold = failure_threshold.to_i
        @cool_down_seconds = cool_down_seconds.to_i
        @failures = 0
        @opened_at = nil
      end

      def allow_request?
        return true if @opened_at.nil?
        return false if (Time.now - @opened_at) < @cool_down_seconds

        @opened_at = nil
        @failures = 0
        true
      end

      def record_success
        @failures = 0
        @opened_at = nil
      end

      def record_failure
        @failures += 1
        @opened_at = Time.now if @failures >= @failure_threshold
      end

      def open?
        !allow_request?
      end
    end
  end
end
