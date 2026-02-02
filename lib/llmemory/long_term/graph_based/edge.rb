# frozen_string_literal: true

module Llmemory
  module LongTerm
    module GraphBased
      Edge = Struct.new(
        :id,
        :user_id,
        :subject_id,
        :predicate,
        :target_id,
        :properties,
        :created_at,
        :archived_at,
        keyword_init: true
      ) do
        def self.from_h(hash)
          new(
            id: hash[:id] || hash["id"],
            user_id: hash[:user_id] || hash["user_id"],
            subject_id: hash[:subject_id] || hash["subject_id"],
            predicate: (hash[:predicate] || hash["predicate"]).to_s,
            target_id: hash[:object_id] || hash["object_id"],
            properties: hash[:properties] || hash["properties"] || {},
            created_at: hash[:created_at] || hash["created_at"],
            archived_at: hash[:archived_at] || hash["archived_at"]
          )
        end

        def archived?
          !archived_at.nil?
        end

        def to_h
          {
            id: id,
            user_id: user_id,
            subject_id: subject_id,
            predicate: predicate,
            object_id: target_id,
            properties: properties || {},
            created_at: created_at,
            archived_at: archived_at
          }
        end
      end
    end
  end
end
