# frozen_string_literal: true

require_relative "base"
require_relative "../../active_record_helpers"

module Llmemory
  module ShortTerm
    module Stores
      class ActiveRecordStore < Base
        include Llmemory::Crypto::FieldHelpers
        include Llmemory::ActiveRecordHelpers

        def initialize(cipher: nil)
          @cipher = cipher || Llmemory.build_cipher
          self.class.load_model!
        end

        def self.load_model!
          return if @model_loaded
          require "active_record"
          require_relative "active_record_checkpoint"
          @model_loaded = true
        end

        def save(user_id, session_id, state)
          with_unique_retry do
            record = Llmemory::ShortTerm::Stores::ActiveRecordCheckpoint.find_or_initialize_by(
              user_id: user_id,
              session_id: session_id
            )
            record.state = cipher.enabled? ? serialize_state(state) : state
            record.updated_at = Time.current
            record.save!
          end
          true
        end

        def load(user_id, session_id)
          record = Llmemory::ShortTerm::Stores::ActiveRecordCheckpoint.find_by(
            user_id: user_id,
            session_id: session_id
          )
          return nil unless record

          raw = record.state
          if raw.is_a?(Hash)
            raw.transform_keys(&:to_sym)
          else
            deserialize_state(raw)
          end
        end

        def delete(user_id, session_id)
          Llmemory::ShortTerm::Stores::ActiveRecordCheckpoint.where(
            user_id: user_id,
            session_id: session_id
          ).destroy_all
          true
        end

        def update(user_id, session_id, &block)
          result = nil
          Llmemory::ShortTerm::Stores::ActiveRecordCheckpoint.transaction do
            record = Llmemory::ShortTerm::Stores::ActiveRecordCheckpoint.lock.find_by(
              user_id: user_id,
              session_id: session_id
            )
            current = if record
                        raw = record.state
                        raw.is_a?(Hash) ? raw.transform_keys(&:to_sym) : deserialize_state(raw)
                      end
            new_state = yield(current)
            next if new_state.nil?

            record ||= Llmemory::ShortTerm::Stores::ActiveRecordCheckpoint.new(
              user_id: user_id,
              session_id: session_id
            )
            record.state = cipher.enabled? ? serialize_state(new_state) : new_state
            record.updated_at = Time.current
            with_unique_retry { record.save! }
            result = new_state
          end
          result
        end

        def list_users
          Llmemory::ShortTerm::Stores::ActiveRecordCheckpoint.distinct.pluck(:user_id)
        end

        def list_sessions(user_id:)
          Llmemory::ShortTerm::Stores::ActiveRecordCheckpoint.where(user_id: user_id).pluck(:session_id)
        end
      end
    end
  end
end
