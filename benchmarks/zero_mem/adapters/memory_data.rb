# frozen_string_literal: true

require "json"
require "yaml"

module ZeroMemBenchmark
  module Adapters
    # Optional bridge to MemoryData datasets checked out locally.
    # Does not vendor MemoryData runtimes or perform HTTP.
    class MemoryData
      def initialize(profile_path: File.expand_path("../profile.yml", __dir__))
        @profile = YAML.safe_load(
          File.read(profile_path),
          permitted_classes: [Symbol],
          aliases: true
        ) || {}
        @root = @profile.dig("memory_data", "dataset_root").to_s
        @commit = @profile.dig("memory_data", "commit")
      end

      def available?
        !@root.empty? && File.directory?(@root)
      end

      def skip_reason
        return "memory_data.dataset_root not configured" if @root.empty?
        return "dataset directory missing: #{@root}" unless File.directory?(@root)

        nil
      end

      def each_conversation
        return enum_for(:each_conversation) unless block_given?
        return unless available?

        Dir.glob(File.join(@root, "**", "*.json")).sort.each do |path|
          yield load_conversation_file(path)
        end
      end

      def metadata
        {
          commit: @commit,
          dataset_root: @root,
          available: available?
        }
      end

      private

      def load_conversation_file(path)
        JSON.parse(File.read(path))
      rescue JSON::ParserError
        { "id" => File.basename(path, ".json"), "source_path" => path, "parse_error" => true }
      end
    end
  end
end
