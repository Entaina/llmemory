# frozen_string_literal: true

require "digest"

module Llmemory
  module ZeroMem
    class Entity
      attr_reader :id, :user_id, :normalized_key, :display_name, :entity_type, :ambiguous

      def self.build(user_id:, normalized_key:, display_name: nil, entity_type: :entity, id: nil, ambiguous: false)
        new(
          id: id || "ent_#{Digest::SHA256.hexdigest([user_id, normalized_key].join(':'))[0, 16]}",
          user_id: user_id.to_s,
          normalized_key: normalized_key.to_s,
          display_name: display_name || normalized_key.to_s,
          entity_type: entity_type.to_sym,
          ambiguous: ambiguous
        )
      end

      def initialize(id:, user_id:, normalized_key:, display_name:, entity_type:, ambiguous:)
        @id = id
        @user_id = user_id
        @normalized_key = normalized_key
        @display_name = display_name
        @entity_type = entity_type
        @ambiguous = ambiguous
      end
    end
  end
end
