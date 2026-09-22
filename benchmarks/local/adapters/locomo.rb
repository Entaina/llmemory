# frozen_string_literal: true

require "json"
require_relative "base"
require_relative "locomo_normalizer"

module LocalBenchmark
  module Adapters
    class LoCoMo < Base
      DEFAULT_FILE = "data/locomo10.json"

      def initialize(root: ENV["LOCOMO_DATASET_ROOT"], file: ENV.fetch("LOCOMO_DATASET_FILE", DEFAULT_FILE))
        @root = root.to_s
        @file = file
      end

      def available?
        !@root.empty? && File.file?(dataset_path)
      end

      def skip_reason
        "Set LOCOMO_DATASET_ROOT to a snap-research/locomo checkout (#{DEFAULT_FILE})"
      end

      def each_conversation
        return enum_for(:each_conversation) unless block_given?
        return unless available?

        samples = JSON.parse(File.read(dataset_path))
        Array(samples).each do |sample|
          yield LocomoNormalizer.normalize_locomo_sample(sample)
        end
      end

      private

      def dataset_path
        path = File.join(@root, @file)
        return path if File.file?(path)

        File.join(@root, "locomo10.json")
      end
    end
  end
end
