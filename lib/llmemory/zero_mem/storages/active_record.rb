# frozen_string_literal: true

require "json"
require_relative "../storage"
require_relative "../../crypto/field_helpers"
require_relative "../../active_record_helpers"

module Llmemory
  module ZeroMem
    module Storages
      class ActiveRecordStorage
        include Storage
        include Llmemory::Crypto::FieldHelpers
        include Llmemory::ActiveRecordHelpers

        def initialize(cipher: nil)
          @cipher = cipher || Llmemory.build_cipher
          self.class.load_models!
        end

        def self.load_models!
          return if @models_loaded

          require "active_record"
          require_relative "active_record_models"
          @models_loaded = true
        end

        def write_trace(trace)
          t = trace.is_a?(Trace) ? trace : Trace.new(**trace)
          if t.idempotency_key && (existing = find_by_idempotency_key(t.user_id, t.idempotency_key))
            return existing.id
          end

          rec = LlmemoryTrace.find_or_initialize_by(id: t.id)
          rec.user_id = t.user_id
          rec.session_id = t.session_id
          rec.boundary_id = t.boundary_id
          rec.sequence = t.sequence
          rec.role = t.role.to_s
          rec.content = enc(t.content)
          rec.content_sha256 = t.content_sha256
          rec.occurred_at = t.occurred_at
          rec.ingested_at = t.ingested_at
          rec.metadata = metadata_column(t.metadata)
          rec.idempotency_key = t.idempotency_key
          rec.archived_at = t.archived_at
          rec.search_tokens = search_tokens_for(t.content) if LlmemoryTrace.column_names.include?("search_tokens")
          with_unique_retry { rec.save! }
          t.id
        end

        def get_trace(user_id, trace_id)
          rec = LlmemoryTrace.find_by(id: trace_id.to_s, user_id: user_id.to_s)
          return nil unless rec

          record_to_trace(rec)
        end

        def find_by_idempotency_key(user_id, idempotency_key)
          return nil if idempotency_key.to_s.empty?

          rec = LlmemoryTrace.find_by(user_id: user_id.to_s, idempotency_key: idempotency_key.to_s)
          rec ? record_to_trace(rec) : nil
        end

        def next_sequence(user_id, session_id)
          max = LlmemoryTrace.where(user_id: user_id.to_s, session_id: session_id.to_s).maximum(:sequence)
          (max || 0) + 1
        end

        def list_traces(user_id, session_id: nil, include_archived: false, limit: nil, offset: nil)
          scope = LlmemoryTrace.where(user_id: user_id.to_s)
          scope = scope.where(session_id: session_id.to_s) if session_id
          scope = scope.where(archived_at: nil) unless include_archived
          scope = scope.order(:session_id, :sequence, :ingested_at)
          scope = scope.offset(offset.to_i) if offset
          scope = scope.limit(limit.to_i) if limit && limit.to_i.positive?
          scope.map { |r| record_to_trace(r) }
        end

        def archive_trace(user_id, trace_id, archived_at: Time.now)
          rec = LlmemoryTrace.find_by(id: trace_id.to_s, user_id: user_id.to_s, archived_at: nil)
          return false unless rec

          rec.update!(archived_at: archived_at)
          true
        end

        def write_state_link(link)
          rec = LlmemoryTraceStateLink.new(
            user_id: link.user_id,
            state_key: link.state_key,
            trace_id: link.trace_id,
            valid_from: link.valid_from,
            valid_to: link.valid_to,
            supersedes_trace_id: link.supersedes_trace_id,
            source: link.source.to_s,
            created_at: link.created_at
          )
          with_unique_retry { rec.save! }
          link.trace_id
        end

        def close_open_state_links(user_id, state_key, valid_to:, except_trace_id: nil)
          scope = LlmemoryTraceStateLink.where(user_id: user_id.to_s, state_key: state_key.to_s, valid_to: nil)
          scope = scope.where.not(trace_id: except_trace_id.to_s) if except_trace_id
          scope.update_all(valid_to: valid_to)
        end

        def state_links_for(user_id, state_key)
          LlmemoryTraceStateLink.where(user_id: user_id.to_s, state_key: state_key.to_s)
                                .order(:valid_from, :created_at)
                                .map { |r| record_to_state_link(r) }
        end

        def current_state_trace_id(user_id, state_key, as_of: Time.now)
          t = as_of.is_a?(Time) ? as_of : Time.parse(as_of.to_s)
          link = LlmemoryTraceStateLink.where(user_id: user_id.to_s, state_key: state_key.to_s)
                                       .where("valid_from <= ?", t)
                                       .where("valid_to IS NULL OR valid_to >= ?", t)
                                       .order(valid_from: :desc, created_at: :desc)
                                       .first
          link&.trace_id
        end

        def get_watermark(user_id, session_id)
          rec = LlmemoryTrace.where(user_id: user_id.to_s, session_id: session_id.to_s)
                             .order(sequence: :desc)
                             .limit(1)
                             .pick(:sequence)
          {
            last_sequence: rec.to_i,
            index_version: rec.to_i
          }
        end

        def set_watermark(user_id, session_id, last_sequence:, index_version:)
          # ZM1: watermark derived from traces; noop placeholder for repair/backfill API.
          { last_sequence: last_sequence.to_i, index_version: index_version.to_i }
        end

        def write_unit(unit)
          return unit.id unless defined?(LlmemoryTraceUnit)

          data = unit.to_h
          rec = LlmemoryTraceUnit.find_or_initialize_by(id: unit.id)
          rec.user_id = unit.user_id
          rec.trace_id = unit.member_trace_ids.first
          rec.unit_type = unit.kind.to_s
          rec.data = cipher.enabled? ? enc_json(data) : data
          with_unique_retry { rec.save! }
          unit.id
        end

        def list_units(user_id, kind: nil, session_id: nil, boundary_id: nil)
          return [] unless defined?(LlmemoryTraceUnit)

          scope = LlmemoryTraceUnit.where(user_id: user_id.to_s, archived_at: nil)
          scope = scope.where(unit_type: kind.to_s) if kind
          scope.map { |r| unit_from_record(r) }
        end

        def get_unit(user_id, unit_id)
          return nil unless defined?(LlmemoryTraceUnit)

          rec = LlmemoryTraceUnit.find_by(id: unit_id.to_s, user_id: user_id.to_s)
          rec ? unit_from_record(rec) : nil
        end

        def open_episode(_user_id, _episode_key)
          nil
        end

        def set_open_episode(_user_id, _episode_key, _unit_id)
          nil
        end

        def close_episode(_unit_id)
          nil
        end

        def upsert_entity(_entity)
          nil
        end

        def write_mention(_mention)
          nil
        end

        def entity_exists?(_user_id, _normalized_key)
          false
        end

        def trace_ids_for_entity_key(_user_id, _normalized_key)
          []
        end

        def entity_keys_for_trace(_user_id, _trace_id)
          []
        end

        def previous_trace(user_id, session_id, sequence)
          list_traces(user_id, session_id: session_id).reverse.find { |t| t.sequence < sequence.to_i }
        end

        def link_adjacent_traces(_user_id, _prev_trace_id, _trace_id)
          nil
        end

        def adjacent_traces(_user_id, _trace_id)
          [nil, nil]
        end

        def store_turn_embedding(_user_id, _trace_id, _vector, model:, dimensions:)
          nil
        end

        def all_entity_keys(_user_id)
          []
        end

        def search_traces_by_tokens(user_id, query, limit: 20)
          scope = LlmemoryTrace.where(user_id: user_id.to_s, archived_at: nil)
          tokens = Llmemory::Tokenizer.tokenize(query)
          return [] if tokens.empty?

          if cipher.enabled? && LlmemoryTrace.column_names.include?("search_tokens")
            digests = tokens.map { |tok| cipher.blind_index(tok) }
            clause = digests.map { "search_tokens LIKE ?" }.join(" OR ")
            scope = scope.where(clause, *digests.map { |d| "% #{d} %" })
            return scope.limit(limit).map { |r| record_to_trace(r) }
          end

          list_traces(user_id, limit: limit).select do |t|
            down = t.content.downcase
            tokens.all? { |tok| down.include?(tok) }
          end
        end

        private

        def cipher
          @cipher
        end

        def metadata_column(metadata)
          meta = metadata || {}
          cipher.enabled? ? enc_json(meta) : meta
        end

        def decode_metadata(value)
          return {} if value.nil?
          return dec_json(value) if cipher.enabled? && value.is_a?(String)

          value.is_a?(Hash) ? value.transform_keys(&:to_sym) : {}
        end

        def record_to_trace(rec)
          Trace.new(
            id: rec.id,
            user_id: rec.user_id,
            session_id: rec.session_id,
            boundary_id: rec.boundary_id,
            sequence: rec.sequence,
            role: rec.role.to_sym,
            content: dec(rec.content),
            occurred_at: rec.occurred_at,
            ingested_at: rec.ingested_at,
            metadata: decode_metadata(rec.metadata),
            content_sha256: rec.content_sha256,
            idempotency_key: rec.idempotency_key,
            archived_at: rec.archived_at
          )
        end

        def record_to_state_link(rec)
          TraceStateLink.new(
            user_id: rec.user_id,
            state_key: rec.state_key,
            trace_id: rec.trace_id,
            valid_from: rec.valid_from,
            valid_to: rec.valid_to,
            supersedes_trace_id: rec.supersedes_trace_id,
            source: rec.source.to_sym,
            created_at: rec.created_at
          )
        end

        def unit_from_record(rec)
          data = rec.data.is_a?(Hash) ? rec.data : dec_json(rec.data)
          data = data.transform_keys(&:to_sym)
          TraceUnit.new(
            id: data[:id] || rec.id,
            user_id: data[:user_id] || rec.user_id,
            kind: (data[:kind] || rec.unit_type).to_sym,
            session_id: data[:session_id],
            boundary_id: data[:boundary_id],
            start_sequence: data[:start_sequence],
            end_sequence: data[:end_sequence],
            occurred_from: Time.parse(data[:occurred_from].to_s),
            occurred_to: Time.parse(data[:occurred_to].to_s),
            member_trace_ids: data[:member_trace_ids] || [],
            embedding_ref: data[:embedding_ref],
            index_version: data[:index_version] || 0
          )
        end
      end
    end
  end
end
