# frozen_string_literal: true

module Llmemory
  module ZeroMem
    # Append-only trace storage contract (ZM1).
    module Storage
      def write_trace(trace)
        raise NotImplementedError
      end

      def get_trace(user_id, trace_id)
        raise NotImplementedError
      end

      def find_by_idempotency_key(user_id, idempotency_key)
        raise NotImplementedError
      end

      def next_sequence(user_id, session_id)
        raise NotImplementedError
      end

      def list_traces(user_id, session_id: nil, include_archived: false, limit: nil, offset: nil)
        raise NotImplementedError
      end

      def archive_trace(user_id, trace_id, archived_at: Time.now)
        raise NotImplementedError
      end

      def write_state_link(link)
        raise NotImplementedError
      end

      def close_open_state_links(user_id, state_key, valid_to:, except_trace_id: nil)
        raise NotImplementedError
      end

      def state_links_for(user_id, state_key)
        raise NotImplementedError
      end

      def current_state_trace_id(user_id, state_key, as_of: Time.now)
        raise NotImplementedError
      end

      def get_watermark(user_id, session_id)
        raise NotImplementedError
      end

      def set_watermark(user_id, session_id, last_sequence:, index_version:)
        raise NotImplementedError
      end

      def search_traces_by_tokens(user_id, query, limit: 20)
        raise NotImplementedError
      end

      def write_unit(unit)
        raise NotImplementedError
      end

      def list_units(user_id, kind: nil, session_id: nil, boundary_id: nil)
        raise NotImplementedError
      end

      def get_unit(user_id, unit_id)
        raise NotImplementedError
      end

      def open_episode(user_id, episode_key)
        raise NotImplementedError
      end

      def set_open_episode(user_id, episode_key, unit_id)
        raise NotImplementedError
      end

      def close_episode(unit_id)
        raise NotImplementedError
      end

      def upsert_entity(entity)
        raise NotImplementedError
      end

      def write_mention(mention)
        raise NotImplementedError
      end

      def entity_exists?(user_id, normalized_key)
        raise NotImplementedError
      end

      def trace_ids_for_entity_key(user_id, normalized_key)
        raise NotImplementedError
      end

      def entity_keys_for_trace(user_id, trace_id)
        raise NotImplementedError
      end

      def previous_trace(user_id, session_id, sequence)
        raise NotImplementedError
      end

      def link_adjacent_traces(user_id, prev_trace_id, trace_id)
        raise NotImplementedError
      end

      def adjacent_traces(user_id, trace_id)
        raise NotImplementedError
      end

      def store_turn_embedding(user_id, trace_id, vector, model:, dimensions:)
        raise NotImplementedError
      end

      def all_entity_keys(user_id)
        raise NotImplementedError
      end
    end
  end
end
