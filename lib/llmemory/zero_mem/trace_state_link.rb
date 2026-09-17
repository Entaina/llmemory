# frozen_string_literal: true

require "time"

module Llmemory
  module ZeroMem
    class TraceStateLink
      SOURCES = %i[explicit deterministic].freeze

      attr_reader :user_id, :state_key, :trace_id, :valid_from, :valid_to,
                  :supersedes_trace_id, :source, :created_at

      def self.build(user_id:, state_key:, trace_id:, valid_from:, valid_to: nil,
                     supersedes_trace_id: nil, source: :explicit, created_at: nil)
        src = source.to_sym
        raise ValidationError, "invalid state link source" unless SOURCES.include?(src)

        new(
          user_id: user_id.to_s,
          state_key: state_key.to_s,
          trace_id: trace_id.to_s,
          valid_from: Trace.coerce_time(valid_from),
          valid_to: valid_to ? Trace.coerce_time(valid_to) : nil,
          supersedes_trace_id: supersedes_trace_id&.to_s,
          source: src,
          created_at: created_at ? Trace.coerce_time(created_at) : Time.now
        )
      end

      def initialize(user_id:, state_key:, trace_id:, valid_from:, valid_to:,
                     supersedes_trace_id:, source:, created_at:)
        @user_id = user_id
        @state_key = state_key
        @trace_id = trace_id
        @valid_from = valid_from
        @valid_to = valid_to
        @supersedes_trace_id = supersedes_trace_id
        @source = source
        @created_at = created_at
      end

      def active_at?(as_of)
        t = as_of.is_a?(Time) ? as_of : Time.parse(as_of.to_s)
        return false if t < valid_from
        return true if valid_to.nil?

        t <= valid_to
      end

      def to_h
        {
          user_id: user_id,
          state_key: state_key,
          trace_id: trace_id,
          valid_from: valid_from.utc.iso8601(6),
          valid_to: valid_to&.utc&.iso8601(6),
          supersedes_trace_id: supersedes_trace_id,
          source: source,
          created_at: created_at.utc.iso8601(6)
        }
      end
    end
  end
end
