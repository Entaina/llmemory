# frozen_string_literal: true

require "time"

module Llmemory
  module LongTerm
    module Procedural
      # A Skill is a reusable procedure an agent can retrieve and apply: a prompt,
      # a template or a snippet of code. This is CoALA's "procedural memory" in the
      # Voyager sense — a growing library of skills the agent learns and reuses.
      #
      # Skills track success/failure outcomes so proven skills can be preferred
      # over unproven ones during retrieval (see #success_rate, and P8 adaptive
      # retrieval).
      class Skill
        KINDS = %w[prompt template code].freeze
        DEFAULT_KIND = "prompt"

        attr_reader :id, :user_id, :name, :description, :body, :kind, :version,
                    :success_count, :failure_count, :provenance, :created_at, :updated_at

        def initialize(id:, user_id:, name:, body:, description: nil, kind: DEFAULT_KIND,
                       version: 1, success_count: 0, failure_count: 0, provenance: nil,
                       created_at: nil, updated_at: nil)
          @id = id
          @user_id = user_id
          @name = name.to_s
          @description = description
          @body = body
          @kind = normalize_kind(kind)
          @version = version.to_i
          @success_count = success_count.to_i
          @failure_count = failure_count.to_i
          @provenance = provenance
          @created_at = created_at || Time.now
          @updated_at = updated_at || @created_at
        end

        # Proven utility in [0, 1]. Unproven skills (no outcomes) are neutral.
        def success_rate
          total = success_count + failure_count
          total.zero? ? 0.5 : success_count.to_f / total
        end

        def searchable_text
          [name, description, body].compact.map(&:to_s).reject(&:empty?).join("\n")
        end

        def normalize_kind(kind)
          k = kind.to_s.strip.downcase
          KINDS.include?(k) ? k : DEFAULT_KIND
        end

        def self.from_h(hash)
          new(
            id: hash[:id] || hash["id"],
            user_id: hash[:user_id] || hash["user_id"],
            name: hash[:name] || hash["name"],
            description: hash[:description] || hash["description"],
            body: hash[:body] || hash["body"],
            kind: hash[:kind] || hash["kind"] || DEFAULT_KIND,
            version: hash[:version] || hash["version"] || 1,
            success_count: hash[:success_count] || hash["success_count"] || 0,
            failure_count: hash[:failure_count] || hash["failure_count"] || 0,
            provenance: hash[:provenance] || hash["provenance"],
            created_at: parse_time(hash[:created_at] || hash["created_at"]),
            updated_at: parse_time(hash[:updated_at] || hash["updated_at"])
          )
        end

        def self.parse_time(value)
          return value if value.nil? || value.is_a?(Time)
          Time.parse(value.to_s)
        rescue ArgumentError
          nil
        end

        def to_h
          {
            id: id,
            user_id: user_id,
            name: name,
            description: description,
            body: body,
            kind: kind,
            version: version,
            success_count: success_count,
            failure_count: failure_count,
            provenance: provenance,
            created_at: created_at.respond_to?(:iso8601) ? created_at.iso8601(6) : created_at,
            updated_at: updated_at.respond_to?(:iso8601) ? updated_at.iso8601(6) : updated_at
          }
        end
      end
    end
  end
end
