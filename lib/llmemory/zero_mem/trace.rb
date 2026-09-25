# frozen_string_literal: true

require "digest"
require "securerandom"
require "time"

module Llmemory
  module ZeroMem
    class Trace
      ATTRS = %i[
        id user_id session_id boundary_id sequence role content occurred_at ingested_at
        metadata content_sha256 idempotency_key archived_at
      ].freeze

      def self.build(user_id:, session_id:, role:, content:, sequence:, id: nil,
                     boundary_id: nil, occurred_at: nil, ingested_at: nil, metadata: nil,
                     idempotency_key: nil, archived_at: nil)
        accepted = normalize_content!(content)
        ingested = ingested_at || Time.now
        occurred_inferred = occurred_at.nil?
        occurred = occurred_at || ingested
        meta = normalize_metadata(metadata)
        meta[:occurred_at_inferred] = true if occurred_inferred

        new(
          id: id || "tr_#{SecureRandom.hex(12)}",
          user_id: user_id.to_s,
          session_id: session_id.to_s,
          boundary_id: boundary_id&.to_s,
          sequence: sequence.to_i,
          role: role.to_sym,
          content: accepted,
          occurred_at: coerce_time(occurred),
          ingested_at: coerce_time(ingested),
          metadata: meta,
          content_sha256: Digest::SHA256.hexdigest(accepted),
          idempotency_key: idempotency_key&.to_s,
          archived_at: archived_at ? coerce_time(archived_at) : nil
        )
      end

      def self.normalize_content!(content)
        text = content.to_s
        unless text.dup.force_encoding(Encoding::UTF_8).valid_encoding?
          raise ValidationError, "trace content must be valid UTF-8"
        end

        text = text.encode(Encoding::UTF_8)
        max = Llmemory.configuration.max_message_chars.to_i
        if max.positive? && text.length > max
          raise ValidationError, "trace content exceeds max_message_chars (#{max})"
        end

        if Llmemory.configuration.message_sanitizer_enabled
          sanitizer = Llmemory::ShortTerm::MessageSanitizer.new
          sanitized = sanitizer.sanitize!([{ role: :user, content: text }])
          text = sanitized.first&.[](:content).to_s
        end

        text
      end

      def self.normalize_metadata(metadata)
        return {} if metadata.nil?
        raise ValidationError, "metadata must be a Hash" unless metadata.is_a?(Hash)

        metadata.transform_keys(&:to_sym)
      end

      def self.coerce_time(value)
        return value if value.is_a?(Time)
        return Time.parse(value.to_s) if value

        Time.now
      end

      attr_reader(*ATTRS)

      def initialize(**attrs)
        ATTRS.each do |key|
          instance_variable_set(:"@#{key}", attrs[key])
        end
      end

      def to_h
        ATTRS.each_with_object({}) do |key, acc|
          val = public_send(key)
          acc[key] = val.is_a?(Time) ? val.utc.iso8601(6) : val
        end
      end

      def active?
        archived_at.nil?
      end

      def with(**changes)
        attrs = ATTRS.to_h { |key| [key, public_send(key)] }.merge(changes)
        self.class.new(**attrs)
      end
    end
  end
end
