# frozen_string_literal: true

require_relative "episode"
require_relative "storage"
require_relative "../../memory_module"
require_relative "../../vector_store"

module Llmemory
  module LongTerm
    module Episodic
      # Episodic long-term memory: records agent trajectories and retrieves them
      # by recency, importance and relevance. Designed to coexist with semantic
      # memory (file/graph), not replace it, and to feed reflection (P2), which
      # distills episodes into semantic knowledge.
      #
      # Recording/retrieval are deterministic and LLM-free by default. Semantic
      # (embedding) retrieval is opt-in via `config.episodic_vector_enabled` or by
      # injecting a `vector_store:`; when off, search is keyword-only (unchanged).
      class Memory
        include Llmemory::MemoryModule

        attr_reader :user_id, :storage

        def initialize(user_id:, storage: nil, vector_store: nil, cipher: nil)
          @user_id = user_id
          @cipher = cipher || Llmemory.build_cipher
          @storage = storage || Storages.build(cipher: @cipher)
          @vector_store = vector_store
          @vector_explicit = !vector_store.nil?
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
          id = @storage.save_episode(@user_id, record)
          index_vector(id, episode.searchable_text)
          id
        end

        def recent_episodes(limit: 10)
          @storage.list_episodes(@user_id, limit: limit).map { |e| Episode.from_h(e) }
        end

        def episodes(limit: nil, offset: nil)
          @storage.list_episodes(@user_id, limit: limit, offset: offset).map { |e| Episode.from_h(e) }
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
        # Hybrid (vector + keyword) when a vector store is active; otherwise
        # keyword-only.
        def search_candidates(query, user_id: nil, top_k: 20)
          uid = user_id || @user_id
          return [] unless uid == @user_id

          keyword = @storage.search_episodes(uid, query).first(top_k).map { |e| candidate_for(e, 1.0) }
          vs = vector_store
          return keyword unless vs

          merge_candidates(vector_candidates(query, top_k, vs), keyword, top_k)
        end

        # --- MemoryModule uniform interface ---

        def write(steps:, summary: nil, outcome: nil, importance: 0.5, **_meta)
          result = nil
          Llmemory::Instrumentation.instrument(:memory_write, memory_type: "episodic", user_id: @user_id) do
            result = record_episode(steps: steps, summary: summary, outcome: outcome, importance: importance)
          end
          result
        end

        def list(user_id: nil, limit: nil, offset: nil)
          episodes(limit: limit, offset: offset)
        end

        def stats(user_id: nil)
          { episodes: count }
        end

        def forget(ids:, reason: nil, mode: :soft)
          requested = Array(ids).map(&:to_s)
          existing = @storage.list_episodes(@user_id).map { |e| (e[:id] || e["id"]).to_s }
          targeted = requested & existing
          count = case mode
          when :hard then @storage.delete_episodes(@user_id, targeted).to_i
          else @storage.archive_episodes(@user_id, targeted).to_i
          end
          forget_log.record(@user_id, memory_type: "episodic", ids: targeted, reason: reason)
          Llmemory::Instrumentation.instrument(:memory_forget, memory_type: "episodic", user_id: @user_id, count: count, mode: mode)
          count
        end

        # Storage accessor for the TTL maintenance job.
        def expired_ids(cutoff:)
          @storage.expired_episode_ids(@user_id, cutoff: cutoff)
        end

        private

        # Active vector store: the injected one, or a config-gated lazy build.
        # Returns nil when semantic search is disabled (default).
        def vector_store
          if @vector_explicit
            @vector_store
          elsif Llmemory.configuration.episodic_vector_enabled
            @vector_store ||= Llmemory::VectorStore.build(source_type: "episode", cipher: @cipher)
          end
        end

        # Best-effort embedding indexing; a failure must never break recording.
        def index_vector(id, text)
          vs = vector_store
          return if vs.nil? || text.to_s.strip.empty?
          embedding = vs.embed(text)
          record_embed_usage(vs)
          return unless embedding
          vs.store(id: id, embedding: embedding, metadata: { text: text, created_at: Time.now }, user_id: @user_id)
        rescue StandardError
          nil
        end

        def vector_candidates(query, top_k, vs)
          results = vs.search_by_text(query.to_s, top_k: top_k, user_id: @user_id)
          record_embed_usage(vs)
          results.filter_map do |r|
            raw = @storage.get_episode(@user_id, r[:id] || r["id"])
            raw && candidate_for(raw, (r[:score] || r["score"] || 1.0).to_f)
          end
        rescue StandardError
          []
        end

        def candidate_for(raw, score)
          episode = Episode.from_h(raw)
          {
            id: episode.id,
            text: episode.summary.to_s.empty? ? episode.searchable_text : episode.summary,
            timestamp: episode.created_at,
            score: score,
            importance: episode.importance,
            evergreen: false,
            provenance: raw[:provenance] || raw["provenance"]
          }
        end

        # Dedup by id keeping the higher score; highest score first, capped.
        def merge_candidates(primary, secondary, top_k)
          by_id = {}
          (primary + secondary).each do |c|
            key = c[:id] || c[:text]
            existing = by_id[key]
            by_id[key] = c if existing.nil? || c[:score].to_f > existing[:score].to_f
          end
          by_id.values.sort_by { |c| -c[:score].to_f }.first(top_k)
        end

        # Cheap, deterministic summary when the caller does not provide one.
        # LLM-based summarization is reflection's job (P2).
        def derive_summary(steps)
          normalized = Episode.normalize_steps(steps)
          return nil if normalized.empty?
          actions = normalized.filter_map { |s| s[:action] }.reject { |a| a.to_s.strip.empty? }
          return nil if actions.empty?
          "Episode with #{normalized.size} step(s): #{actions.join(' -> ')}"
        end

        def record_embed_usage(vector_store)
          Llmemory::LLM::UsageRecorder.record_embed_from_store(
            user_id: @user_id,
            vector_store: vector_store,
            store: Llmemory::ShortTerm::Stores.build(cipher: @cipher)
          )
        end
      end
    end
  end
end
