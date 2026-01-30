# frozen_string_literal: true

require_relative "base"

module Llmemory
  module ShortTerm
    module Stores
      class ActiveRecordStore < Base
        def initialize
          self.class.load_model!
        end

        def self.load_model!
          return if @model_loaded
          require "active_record"
          require_relative "active_record_checkpoint"
          @model_loaded = true
        end

        def save(user_id, session_id, state)
          record = Llmemory::ShortTerm::Stores::ActiveRecordCheckpoint.find_or_initialize_by(
            user_id: user_id,
            session_id: session_id
          )
          record.state = state
          record.updated_at = Time.current
          record.save!
          true
        end

        def load(user_id, session_id)
          record = Llmemory::ShortTerm::Stores::ActiveRecordCheckpoint.find_by(
            user_id: user_id,
            session_id: session_id
          )
          return nil unless record
          raw = record.state
          raw.is_a?(Hash) ? raw.transform_keys(&:to_sym) : deserialize(raw)
        end

        def delete(user_id, session_id)
          Llmemory::ShortTerm::Stores::ActiveRecordCheckpoint.where(
            user_id: user_id,
            session_id: session_id
          ).destroy_all
          true
        end

        private

        def deserialize(data)
          return data if data.is_a?(Hash)
          JSON.parse(data.to_s, symbolize_names: true)
        end
      end
    end
  end
end
