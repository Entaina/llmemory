# frozen_string_literal: true

require_relative "external_dataset"

module ZeroMemBenchmark
  module Adapters
    # Placeholder until DB-Bench / LifelongAgentBench adapter exists.
    class Procedural < ExternalDataset
      def available?
        false
      end

      def skip_reason
        "Procedural state-final adapter not wired yet; use spec/fixtures/zero_mem procedural fixtures"
      end
    end
  end
end
