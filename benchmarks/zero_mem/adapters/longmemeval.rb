# frozen_string_literal: true

require_relative "external_dataset"

module ZeroMemBenchmark
  module Adapters
    class LongMemEval < ExternalDataset
      def initialize(root: ENV["LONGMEMEVAL_DATASET_ROOT"])
        @root = root.to_s
      end

      def available?
        !@root.empty? && File.directory?(@root)
      end

      def skip_reason
        "Set LONGMEMEVAL_DATASET_ROOT to a local checkout"
      end

      def each_conversation
        return enum_for(:each_conversation) unless block_given?
      end
    end
  end
end
