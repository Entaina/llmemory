# frozen_string_literal: true

require "json"
require_relative "external_dataset"

module ZeroMemBenchmark
  module Adapters
    class LoCoMo < ExternalDataset
      def initialize(root: ENV["LOCOMO_DATASET_ROOT"])
        @root = root.to_s
      end

      def available?
        !@root.empty? && File.directory?(@root)
      end

      def skip_reason
        "Set LOCOMO_DATASET_ROOT to a local checkout"
      end

      def each_conversation
        return enum_for(:each_conversation) unless block_given?
        return unless available?

        Dir.glob(File.join(@root, "**/*.json")).sort.each do |path|
          data = JSON.parse(File.read(path))
          yield data.merge("source_path" => path)
        end
      end
    end
  end
end
