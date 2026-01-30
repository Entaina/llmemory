# frozen_string_literal: true

module Llmemory
  module LongTerm
    module FileBased
      class Category
        attr_reader :user_id, :name, :content, :updated_at

        def initialize(user_id:, name:, content: "", updated_at: nil)
          @user_id = user_id
          @name = name
          @content = content
          @updated_at = updated_at || Time.now
        end

        def to_h
          { user_id: user_id, name: name, content: content, updated_at: updated_at.iso8601 }
        end
      end
    end
  end
end
