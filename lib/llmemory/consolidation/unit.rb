# frozen_string_literal: true

module Llmemory
  module Consolidation
    # Normalized fact unit passed to Consolidation::Policy.
    # kind: :relation (graph) | :item (file-based)
    Unit = Data.define(:kind, :subject, :predicate, :object, :content, :category, :importance) do
      def self.from_relation(relation)
        new(
          kind: :relation,
          subject: normalize_string(relation[:subject] || relation["subject"]),
          predicate: normalize_predicate(relation[:predicate] || relation["predicate"]),
          object: normalize_string(relation[:object] || relation["object"]),
          content: nil,
          category: nil,
          importance: nil
        )
      end

      def self.from_item(item, category: nil)
        content = if item.is_a?(Hash)
          (item["content"] || item[:content]).to_s
        else
          item.to_s
        end
        importance = if item.is_a?(Hash)
          item["importance"] || item[:importance]
        end

        new(
          kind: :item,
          subject: nil,
          predicate: nil,
          object: nil,
          content: content,
          category: normalize_category(category),
          importance: importance
        )
      end

      def self.normalize_predicate(value)
        normalize_string(value).downcase.gsub(/\s+/, "_")
      end

      def self.normalize_category(value)
        normalize_string(value).downcase.gsub(/\s+/, "_")
      end

      def self.normalize_string(value)
        value.to_s.strip
      end
    end
  end
end
