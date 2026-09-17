# frozen_string_literal: true

require_relative "external_dataset"

module ZeroMemBenchmark
  module Adapters
    class LongBench < ExternalDataset
      def initialize(root: ENV["LONGBENCH_DATASET_ROOT"])
        @root = root.to_s
      end

      def available?
        !@root.empty? && File.directory?(@root)
      end

      def skip_reason
        "Set LONGBENCH_DATASET_ROOT to a local checkout"
      end
    end
  end
end
