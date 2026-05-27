# frozen_string_literal: true

module Llmemory
  module LongTerm
    module GraphBased
      Node = Struct.new(
        :id,
        :user_id,
        :entity_type,
        :name,
        :properties,
        :created_at,
        :updated_at,
        keyword_init: true
      ) do
        def self.from_h(hash)
          new(
            id: hash[:id] || hash["id"],
            user_id: hash[:user_id] || hash["user_id"],
            entity_type: (hash[:entity_type] || hash["entity_type"]).to_s,
            name: (hash[:name] || hash["name"]).to_s,
            properties: hash[:properties] || hash["properties"] || {},
            created_at: hash[:created_at] || hash["created_at"],
            updated_at: hash[:updated_at] || hash["updated_at"]
          )
        end

        # Lineage of this node, stored within properties so it round-trips
        # through every backend without a schema change. See Llmemory::Provenance.
        def provenance
          props = properties || {}
          props[:provenance] || props["provenance"]
        end

        def to_h
          {
            id: id,
            user_id: user_id,
            entity_type: entity_type,
            name: name,
            properties: properties || {},
            created_at: created_at,
            updated_at: updated_at
          }
        end
      end
    end
  end
end
