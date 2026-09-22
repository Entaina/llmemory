# frozen_string_literal: true

require "json"
require_relative "base"
require_relative "locomo_plus_stitcher"

module LocalBenchmark
  module Adapters
    class LoCoMoPlus < Base
      PLUS_FILE = "locomo_plus.json"

      def initialize(root: ENV["LOCOMO_PLUS_DATASET_ROOT"])
        @root = root.to_s
      end

      def available?
        !@root.empty? && File.file?(plus_path) && !locomo_samples.empty?
      end

      def skip_reason
        "Set LOCOMO_PLUS_DATASET_ROOT with #{PLUS_FILE} and locomo10.json"
      end

      def each_conversation
        return enum_for(:each_conversation) unless block_given?
        return unless available?

        rows = JSON.parse(File.read(plus_path))
        Array(rows).each_with_index do |row, idx|
          yield LoCoMoPlusStitcher.stitch(row, idx, locomo_samples)
        end
      end

      private

      def plus_path
        direct = File.join(@root, PLUS_FILE)
        return direct if File.file?(direct)

        File.join(@root, "data", PLUS_FILE)
      end

      def locomo_samples
        @locomo_samples ||= LoCoMoPlusStitcher.load_locomo10_samples(@root)
      end
    end
  end
end
