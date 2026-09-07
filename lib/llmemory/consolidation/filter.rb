# frozen_string_literal: true

module Llmemory
  module Consolidation
    module Filter
      VOLATILE_PROPERTY = "consolidation_volatile"
      VOLATILE_PROVENANCE_FLAG = "volatile"

      module_function

      def policy
        Llmemory.configuration.consolidation_policy || NullPolicy.new
      end

      # @return [Array<Hash>] relations with :volatile key
      def apply_relations(relations)
        Array(relations).filter_map do |relation|
          next unless relation.is_a?(Hash)

          unit = Unit.from_relation(relation)
          case policy.decide(unit)
          when :drop
            next
          when :volatile
            relation.merge(volatile: true)
          else
            relation.merge(volatile: false)
          end
        end
      end

      # @return [Array<Hash>] item hashes with :volatile key
      def apply_items(items, classifications = {})
        Array(items).filter_map do |item|
          content = item.is_a?(Hash) ? (item["content"] || item[:content]).to_s : item.to_s
          category = classifications[content] || classifications[content.to_sym]
          unit = Unit.from_item(item, category: category)

          case policy.decide(unit)
          when :drop
            next
          when :volatile
            item_hash = item.is_a?(Hash) ? item.dup : {"content" => content}
            item_hash.merge(volatile: true)
          else
            item_hash = item.is_a?(Hash) ? item.dup : {"content" => content}
            item_hash.merge(volatile: false)
          end
        end
      end

      def volatile_provenance(base_provenance)
        prov = base_provenance.is_a?(Hash) ? base_provenance.dup : {}
        prov[:consolidation] = VOLATILE_PROVENANCE_FLAG
        prov["consolidation"] = VOLATILE_PROVENANCE_FLAG unless prov.key?(:consolidation)
        prov
      end

      def volatile_properties(base_properties)
        props = base_properties.is_a?(Hash) ? base_properties.dup : {}
        props[VOLATILE_PROPERTY] = true
        props
      end

      def volatile_marked?(properties_or_provenance)
        hash = properties_or_provenance || {}
        hash[VOLATILE_PROPERTY] == true ||
          hash["consolidation_volatile"] == true ||
          hash[:consolidation] == VOLATILE_PROVENANCE_FLAG ||
          hash["consolidation"] == VOLATILE_PROVENANCE_FLAG
      end
    end
  end
end
