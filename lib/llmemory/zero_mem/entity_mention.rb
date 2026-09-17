# frozen_string_literal: true

module Llmemory
  module ZeroMem
    class EntityMention
      attr_reader :id, :user_id, :trace_id, :entity_id, :normalized_key, :text, :offset_start, :offset_end

      def self.build(user_id:, trace_id:, entity_id:, normalized_key:, text:, offset_start: 0, offset_end: nil, id: nil)
        new(
          id: id || "men_#{SecureRandom.hex(8)}",
          user_id: user_id.to_s,
          trace_id: trace_id.to_s,
          entity_id: entity_id.to_s,
          normalized_key: normalized_key.to_s,
          text: text.to_s,
          offset_start: offset_start.to_i,
          offset_end: (offset_end || offset_start.to_i + text.to_s.length).to_i
        )
      end

      def initialize(id:, user_id:, trace_id:, entity_id:, normalized_key:, text:, offset_start:, offset_end:)
        @id = id
        @user_id = user_id
        @trace_id = trace_id
        @entity_id = entity_id
        @normalized_key = normalized_key
        @text = text
        @offset_start = offset_start
        @offset_end = offset_end
      end
    end
  end
end

require "securerandom"
