# frozen_string_literal: true

require "securerandom"

module Llmemory
  module Maintenance
    class Consolidator
      def initialize(storage)
        @storage = storage
      end

      def run_nightly(user_id)
        recent = @storage.get_items_since(user_id, hours: 24)
        duplicates = find_duplicates(recent)

        duplicates.each do |group|
          merged = merge_items(group)
          ids = group.map { |i| i[:id] }
          @storage.replace_items(user_id, ids, merged)
        end

        true
      end

      private

      def find_duplicates(items)
        groups = []
        seen = {}
        items.each do |item|
          key = normalize_content(item[:content].to_s)
          next if key.empty?
          seen[key] ||= []
          seen[key] << item
        end
        seen.each_value { |v| groups << v if v.size > 1 }
        groups
      end

      def normalize_content(content)
        content.to_s.downcase.gsub(/\s+/, " ").strip[0..200]
      end

      def merge_items(group)
        contents = group.map { |i| i[:content].to_s }.uniq
        {
          id: "merged_#{SecureRandom.hex(4)}",
          category: group.first[:category],
          content: contents.join("; "),
          source_resource_id: group.first[:source_resource_id]
        }
      end
    end
  end
end
