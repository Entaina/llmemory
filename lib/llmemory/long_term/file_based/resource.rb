# frozen_string_literal: true

module Llmemory
  module LongTerm
    module FileBased
      class Resource
        attr_reader :id, :user_id, :text, :created_at

        def initialize(id:, user_id:, text:, created_at: nil)
          @id = id
          @user_id = user_id
          @text = text
          @created_at = created_at || Time.now
        end

        def to_h
          { id: id, user_id: user_id, text: text, created_at: created_at.iso8601 }
        end
      end
    end
  end
end
