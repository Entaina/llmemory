# frozen_string_literal: true

require_relative "skill"
require_relative "storage"
require_relative "../../memory_module"

module Llmemory
  module LongTerm
    module Procedural
      # Procedural long-term memory: a Voyager-style skill library. Agents
      # register reusable skills (prompts, templates, code), retrieve them by
      # relevance to the current task, and report outcomes so proven skills are
      # preferred over unproven ones.
      #
      # Retrieval is keyword-based for now (vector search is a follow-up). The
      # success rate of each skill is surfaced as `importance`, so the retrieval
      # Engine ranks battle-tested skills higher (P3 importance weighting).
      class Memory
        include Llmemory::MemoryModule

        attr_reader :user_id, :storage

        def initialize(user_id:, storage: nil)
          @user_id = user_id
          @storage = storage || Storages.build
        end

        # Registers a skill. If `version` is omitted and a skill with the same
        # name exists, the version auto-increments (skill evolution).
        def register_skill(name:, body:, description: nil, kind: Skill::DEFAULT_KIND, version: nil)
          version ||= next_version_for(name)
          skill = Skill.new(
            id: nil, user_id: @user_id, name: name, body: body,
            description: description, kind: kind, version: version
          )
          @storage.save_skill(@user_id, skill.to_h)
        end

        def find_skill(query)
          raw = @storage.search_skills(@user_id, query).first
          raw && Skill.from_h(raw)
        end

        def get_skill(id)
          raw = @storage.get_skill(@user_id, id)
          raw && Skill.from_h(raw)
        end

        def skills(limit: nil)
          @storage.list_skills(@user_id, limit: limit).map { |s| Skill.from_h(s) }
        end

        def count
          @storage.count_skills(@user_id)
        end

        # Records that applying a skill succeeded or failed. Feeds retrieval
        # ranking and adaptive retrieval (P8). Returns the updated Skill.
        def report_outcome(skill_id, success:)
          raw = @storage.record_outcome(@user_id, skill_id, success: success)
          raw && Skill.from_h(raw)
        end

        # Retrieval Engine integration: skills ranked by relevance, recency and
        # proven utility (success rate exposed as importance).
        def search_candidates(query, user_id: nil, top_k: 20)
          uid = user_id || @user_id
          return [] unless uid == @user_id

          @storage.search_skills(uid, query).first(top_k).map do |raw|
            skill = Skill.from_h(raw)
            {
              id: skill.id,
              text: skill.searchable_text,
              timestamp: skill.created_at,
              score: 1.0,
              importance: skill.success_rate,
              evergreen: false
            }
          end
        end

        # --- MemoryModule uniform interface ---

        def write(name:, body:, description: nil, kind: Skill::DEFAULT_KIND, version: nil, **_meta)
          register_skill(name: name, body: body, description: description, kind: kind, version: version)
        end

        def list(user_id: nil, limit: nil)
          skills(limit: limit)
        end

        def stats(user_id: nil)
          { skills: count }
        end

        def forget(ids:, reason: nil)
          requested = Array(ids).map(&:to_s)
          existing = @storage.list_skills(@user_id).map { |s| (s[:id] || s["id"]).to_s }
          removed = requested & existing
          @storage.delete_skills(@user_id, removed)
          forget_log.record(@user_id, memory_type: "procedural", ids: removed, reason: reason)
          removed.size
        end

        private

        def next_version_for(name)
          existing = @storage.find_skills_by_name(@user_id, name)
          return 1 if existing.empty?
          existing.map { |s| (s[:version] || s["version"] || 1).to_i }.max + 1
        end
      end
    end
  end
end
