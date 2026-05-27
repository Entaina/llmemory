# frozen_string_literal: true

require_relative "episode"
require_relative "storage"
require_relative "../../memory_module"

module Llmemory
  module LongTerm
    module Episodic
      # Episodic long-term memory: records agent trajectories and retrieves them
      # by recency, importance and relevance. Designed to coexist with semantic
      # memory (file/graph), not replace it, and to feed reflection (P2), which
      # distills episodes into semantic knowledge.
      #
      # Deliberately LLM-free: recording and retrieval are deterministic. Higher
      # order summarization belongs to reflection.
      class Memory
        include Llmemory::MemoryModule

        attr_reader :user_id, :storage

        def initialize(user_id:, storage: nil)
          @user_id = user_id
          @storage = storage || Storages.build
        end

        # Records a trajectory. `steps` is an array of hashes with any of
        # :observation, :action, :result, :timestamp. Returns the episode id.
        def record_episode(steps:, summary: nil, outcome: nil, importance: 0.5)
          episode = Episode.new(
            id: nil,
            user_id: @user_id,
            steps: steps,
            summary: summary || derive_summary(steps),
            outcome: outcome,
            importance: importance
          )
          provenance = Llmemory::Provenance.from_text_fingerprint(
            episode.searchable_text, method: "episode_recording", confidence: episode.importance
          )
          record = episode.to_h.merge(provenance: provenance)
          @storage.save_episode(@user_id, record)
        end

        def recent_episodes(limit: 10)
          @storage.list_episodes(@user_id, limit: limit).map { |e| Episode.from_h(e) }
        end

        def episodes(limit: nil)
          @storage.list_episodes(@user_id, limit: limit).map { |e| Episode.from_h(e) }
        end

        def find_episode(id)
          raw = @storage.get_episode(@user_id, id)
          raw && Episode.from_h(raw)
        end

        def count
          @storage.count_episodes(@user_id)
        end

        # Retrieval Engine integration. Returns candidates shaped like the other
        # long-term memories so the Engine can rank episodes by relevance,
        # recency (temporal decay) and importance (P3), with provenance (P10).
        def search_candidates(query, user_id: nil, top_k: 20)
          uid = user_id || @user_id
          return [] unless uid == @user_id

          @storage.search_episodes(uid, query).first(top_k).map do |e|
            episode = Episode.from_h(e)
            {
              id: episode.id,
              text: episode.summary.to_s.empty? ? episode.searchable_text : episode.summary,
              timestamp: episode.created_at,
              score: 1.0,
              importance: episode.importance,
              evergreen: false,
              provenance: e[:provenance] || e["provenance"]
            }
          end
        end

        # --- MemoryModule uniform interface ---

        def write(steps:, summary: nil, outcome: nil, importance: 0.5, **_meta)
          record_episode(steps: steps, summary: summary, outcome: outcome, importance: importance)
        end

        def list(user_id: nil, limit: nil)
          episodes(limit: limit)
        end

        def stats(user_id: nil)
          { episodes: count }
        end

        def forget(ids:, reason: nil)
          requested = Array(ids).map(&:to_s)
          existing = @storage.list_episodes(@user_id).map { |e| (e[:id] || e["id"]).to_s }
          removed = requested & existing
          @storage.delete_episodes(@user_id, removed)
          forget_log.record(@user_id, memory_type: "episodic", ids: removed, reason: reason)
          removed.size
        end

        private

        # Cheap, deterministic summary when the caller does not provide one.
        # LLM-based summarization is reflection's job (P2).
        def derive_summary(steps)
          normalized = Episode.normalize_steps(steps)
          return nil if normalized.empty?
          actions = normalized.filter_map { |s| s[:action] }.reject { |a| a.to_s.strip.empty? }
          return nil if actions.empty?
          "Episode with #{normalized.size} step(s): #{actions.join(' -> ')}"
        end
      end
    end
  end
end
