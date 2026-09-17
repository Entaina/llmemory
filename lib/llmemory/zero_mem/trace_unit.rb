# frozen_string_literal: true

require "securerandom"

module Llmemory
  module ZeroMem
    class TraceUnit
      KINDS = %i[turn window episode].freeze

      attr_reader :id, :user_id, :kind, :session_id, :boundary_id, :start_sequence, :end_sequence,
                  :occurred_from, :occurred_to, :member_trace_ids, :embedding_ref, :index_version

      def self.build(user_id:, kind:, session_id:, member_trace_ids:, start_sequence:, end_sequence:,
                     occurred_from:, occurred_to:, id: nil, boundary_id: nil, embedding_ref: nil,
                     index_version: 0)
        k = kind.to_sym
        raise ValidationError, "invalid trace unit kind" unless KINDS.include?(k)

        new(
          id: id || "tu_#{SecureRandom.hex(10)}",
          user_id: user_id.to_s,
          kind: k,
          session_id: session_id.to_s,
          boundary_id: boundary_id&.to_s,
          start_sequence: start_sequence.to_i,
          end_sequence: end_sequence.to_i,
          occurred_from: Trace.coerce_time(occurred_from),
          occurred_to: Trace.coerce_time(occurred_to),
          member_trace_ids: Array(member_trace_ids).map(&:to_s),
          embedding_ref: embedding_ref,
          index_version: index_version.to_i
        )
      end

      def initialize(id:, user_id:, kind:, session_id:, boundary_id:, start_sequence:, end_sequence:,
                     occurred_from:, occurred_to:, member_trace_ids:, embedding_ref:, index_version:)
        @id = id
        @user_id = user_id
        @kind = kind
        @session_id = session_id
        @boundary_id = boundary_id
        @start_sequence = start_sequence
        @end_sequence = end_sequence
        @occurred_from = occurred_from
        @occurred_to = occurred_to
        @member_trace_ids = member_trace_ids
        @embedding_ref = embedding_ref
        @index_version = index_version
      end

      def episode_key
        boundary_id || session_id
      end

      def to_h
        {
          id: id,
          user_id: user_id,
          kind: kind,
          session_id: session_id,
          boundary_id: boundary_id,
          start_sequence: start_sequence,
          end_sequence: end_sequence,
          occurred_from: occurred_from.utc.iso8601(6),
          occurred_to: occurred_to.utc.iso8601(6),
          member_trace_ids: member_trace_ids,
          embedding_ref: embedding_ref,
          index_version: index_version
        }
      end

      def with(**changes)
        attrs = {
          id: id, user_id: user_id, kind: kind, session_id: session_id, boundary_id: boundary_id,
          start_sequence: start_sequence, end_sequence: end_sequence,
          occurred_from: occurred_from, occurred_to: occurred_to,
          member_trace_ids: member_trace_ids, embedding_ref: embedding_ref, index_version: index_version
        }.merge(changes)
        self.class.new(**attrs)
      end
    end
  end
end
