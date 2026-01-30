# frozen_string_literal: true

module Llmemory
  module LongTerm
    module FileBased
      class Item
        attr_reader :id, :user_id, :category, :content, :source_resource_id, :created_at

        def initialize(id:, user_id:, category:, content:, source_resource_id: nil, created_at: nil)
          @id = id
          @user_id = user_id
          @category = category
          @content = content
          @source_resource_id = source_resource_id
          @created_at = created_at || Time.now
        end

        def to_h
          {
            id: id,
            user_id: user_id,
            category: category,
            content: content,
            source_resource_id: source_resource_id,
            created_at: created_at.iso8601
          }
        end
      end
    end
  end
end
