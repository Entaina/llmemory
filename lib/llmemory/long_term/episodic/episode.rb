# frozen_string_literal: true

require "time"

module Llmemory
  module LongTerm
    module Episodic
      # An Episode is a trajectory of an agent's experience: an ordered list of
      # steps (observation -> action -> result) plus a summary, an outcome label
      # and an importance score. This is CoALA's "episodic memory" — distinct
      # from semantic memory (facts), it stores what happened so it can later be
      # retrieved as examples or distilled into semantic knowledge (see P2,
      # reflection).
      class Episode
        attr_reader :id, :user_id, :steps, :summary, :outcome, :importance, :provenance, :created_at

        STEP_KEYS = %i[observation action result timestamp].freeze

        def initialize(id:, user_id:, steps: [], summary: nil, outcome: nil, importance: 0.5, provenance: nil, created_at: nil)
          @id = id
          @user_id = user_id
          @steps = self.class.normalize_steps(steps)
          @summary = summary
          @outcome = outcome
          @importance = importance.nil? ? 0.5 : importance.to_f
          @provenance = provenance
          @created_at = created_at || Time.now
        end

        # Flat, searchable representation used for keyword retrieval and, in the
        # future, embedding. Combines summary, outcome and every step field.
        def searchable_text
          parts = [summary, outcome]
          steps.each do |s|
            parts << s[:observation]
            parts << s[:action]
            parts << s[:result]
          end
          parts.compact.map(&:to_s).reject(&:empty?).join("\n")
        end

        def self.normalize_steps(steps)
          Array(steps).filter_map do |step|
            next nil unless step.is_a?(Hash)
            {
              observation: step[:observation] || step["observation"],
              action: step[:action] || step["action"],
              result: step[:result] || step["result"],
              timestamp: normalize_time(step[:timestamp] || step["timestamp"])
            }
          end
        end

        def self.normalize_time(value)
          return nil if value.nil?
          value.respond_to?(:iso8601) ? value.iso8601 : value.to_s
        end

        def self.from_h(hash)
          new(
            id: hash[:id] || hash["id"],
            user_id: hash[:user_id] || hash["user_id"],
            steps: hash[:steps] || hash["steps"] || [],
            summary: hash[:summary] || hash["summary"],
            outcome: hash[:outcome] || hash["outcome"],
            importance: hash[:importance] || hash["importance"] || 0.5,
            provenance: hash[:provenance] || hash["provenance"],
            created_at: parse_created_at(hash[:created_at] || hash["created_at"])
          )
        end

        def self.parse_created_at(value)
          return value if value.nil? || value.is_a?(Time)
          Time.parse(value.to_s)
        rescue ArgumentError
          nil
        end

        def to_h
          {
            id: id,
            user_id: user_id,
            steps: steps,
            summary: summary,
            outcome: outcome,
            importance: importance,
            provenance: provenance,
            created_at: created_at.respond_to?(:iso8601) ? created_at.iso8601(6) : created_at
          }
        end
      end
    end
  end
end
