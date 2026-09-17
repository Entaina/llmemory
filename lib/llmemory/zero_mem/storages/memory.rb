# frozen_string_literal: true

require_relative "../storage"

module Llmemory
  module ZeroMem
    module Storages
      class Memory
        include Storage

        def initialize
          @traces = {}
          @idempotency = {}
          @sequences = Hash.new(0)
          @state_links = []
          @watermarks = {}
          @units = {}
          @open_episodes = {}
          @entities = {}
          @mentions = []
          @entity_traces = Hash.new { |h, k| h[k] = [] }
          @trace_entity_keys = Hash.new { |h, k| h[k] = [] }
          @adjacency = {}
          @turn_embeddings = {}
        end

        def write_trace(trace)
          t = trace.is_a?(Trace) ? trace : Trace.new(**trace)
          key = idempotency_key(t.user_id, t.idempotency_key)
          if key && @idempotency[key]
            return @idempotency[key]
          end
          if t.idempotency_key && (existing = find_by_idempotency_key(t.user_id, t.idempotency_key))
            return existing.id
          end

          @traces[t.id] = t
          @idempotency[key] = t.id if key
          @sequences[[t.user_id, t.session_id]] = t.sequence if t.sequence > @sequences[[t.user_id, t.session_id]]
          t.id
        end

        def get_trace(user_id, trace_id)
          t = @traces[trace_id.to_s]
          return nil unless t
          return nil unless t.user_id == user_id.to_s

          t
        end

        def find_by_idempotency_key(user_id, idempotency_key)
          id = @idempotency[idempotency_key(user_id, idempotency_key)]
          id ? get_trace(user_id, id) : nil
        end

        def next_sequence(user_id, session_id)
          @sequences[[user_id.to_s, session_id.to_s]] + 1
        end

        def list_traces(user_id, session_id: nil, include_archived: false, limit: nil, offset: nil)
          uid = user_id.to_s
          list = @traces.values.select do |t|
            next false unless t.user_id == uid
            next false if session_id && t.session_id != session_id.to_s
            next false if !include_archived && !t.active?

            true
          end
          list.sort_by! { |t| [t.session_id, t.sequence, t.ingested_at.to_f] }
          list = list.drop(offset.to_i) if offset
          list = list.first(limit.to_i) if limit && limit.to_i.positive?
          list
        end

        def archive_trace(user_id, trace_id, archived_at: Time.now)
          t = get_trace(user_id, trace_id)
          return false unless t

          @traces[t.id] = t.with(archived_at: archived_at)
          cascade_archive_derivatives(user_id, t.id)
          true
        end

        def write_state_link(link)
          @state_links << link
          link.trace_id
        end

        def close_open_state_links(user_id, state_key, valid_to:, except_trace_id: nil)
          uid = user_id.to_s
          sk = state_key.to_s
          closed = 0
          @state_links.each_with_index do |link, idx|
            next unless link.user_id == uid && link.state_key == sk
            next unless link.valid_to.nil?
            next if except_trace_id && link.trace_id == except_trace_id.to_s

            @state_links[idx] = TraceStateLink.new(
              user_id: link.user_id,
              state_key: link.state_key,
              trace_id: link.trace_id,
              valid_from: link.valid_from,
              valid_to: valid_to,
              supersedes_trace_id: link.supersedes_trace_id,
              source: link.source,
              created_at: link.created_at
            )
            closed += 1
          end
          closed
        end

        def state_links_for(user_id, state_key)
          @state_links.select { |l| l.user_id == user_id.to_s && l.state_key == state_key.to_s }
                      .sort_by { |l| [l.valid_from.to_f, l.created_at.to_f] }
        end

        def current_state_trace_id(user_id, state_key, as_of: Time.now)
          state_links_for(user_id, state_key).reverse.find { |l| l.active_at?(as_of) }&.trace_id
        end

        def get_watermark(user_id, session_id)
          @watermarks[[user_id.to_s, session_id.to_s]] || { last_sequence: 0, index_version: 0 }
        end

        def set_watermark(user_id, session_id, last_sequence:, index_version:)
          @watermarks[[user_id.to_s, session_id.to_s]] = {
            last_sequence: last_sequence.to_i,
            index_version: index_version.to_i
          }
        end

        def write_unit(unit)
          u = unit.is_a?(TraceUnit) ? unit : TraceUnit.new(**unit)
          @units[u.id] = u
          u.id
        end

        def list_units(user_id, kind: nil, session_id: nil, boundary_id: nil)
          uid = user_id.to_s
          @units.values.select do |u|
            next false unless u.user_id == uid
            next false if kind && u.kind != kind.to_sym
            next false if session_id && u.session_id != session_id.to_s
            next false if boundary_id && u.boundary_id != boundary_id.to_s
            next false if unit_references_archived_trace?(u)

            true
          end.sort_by { |u| [u.kind.to_s, u.start_sequence, u.end_sequence] }
        end

        def get_unit(user_id, unit_id)
          u = @units[unit_id.to_s]
          return nil unless u
          return nil unless u.user_id == user_id.to_s

          u
        end

        def open_episode(user_id, episode_key)
          id = @open_episodes[[user_id.to_s, episode_key.to_s]]
          id ? get_unit(user_id, id) : nil
        end

        def set_open_episode(user_id, episode_key, unit_id)
          @open_episodes[[user_id.to_s, episode_key.to_s]] = unit_id.to_s
        end

        def close_episode(unit_id)
          @open_episodes.delete_if { |_, v| v == unit_id.to_s }
        end

        def upsert_entity(entity)
          ent = entity.is_a?(Entity) ? entity : Entity.new(**entity)
          key = [ent.user_id, ent.normalized_key]
          @entities[key] = ent
          ent.id
        end

        def write_mention(mention)
          m = mention.is_a?(EntityMention) ? mention : EntityMention.new(**mention)
          @mentions << m
          @entity_traces[[m.user_id, m.normalized_key]] << m.trace_id unless @entity_traces[[m.user_id, m.normalized_key]].include?(m.trace_id)
          @trace_entity_keys[[m.user_id, m.trace_id]] << m.normalized_key unless @trace_entity_keys[[m.user_id, m.trace_id]].include?(m.normalized_key)
          m.id
        end

        def entity_exists?(user_id, normalized_key)
          @entities.key?([user_id.to_s, normalized_key.to_s])
        end

        def trace_ids_for_entity_key(user_id, normalized_key)
          @entity_traces[[user_id.to_s, normalized_key.to_s]].select do |tid|
            active_trace?(user_id, tid)
          end
        end

        def entity_keys_for_trace(user_id, trace_id)
          @trace_entity_keys[[user_id.to_s, trace_id.to_s]].dup
        end

        def previous_trace(user_id, session_id, sequence)
          list_traces(user_id, session_id: session_id).reverse.find { |t| t.sequence < sequence.to_i }
        end

        def link_adjacent_traces(user_id, prev_trace_id, trace_id)
          uid = user_id.to_s
          @adjacency[prev_trace_id.to_s] ||= {}
          @adjacency[prev_trace_id.to_s][:next] = trace_id.to_s
          @adjacency[trace_id.to_s] ||= {}
          @adjacency[trace_id.to_s][:prev] = prev_trace_id.to_s
        end

        def adjacent_traces(user_id, trace_id)
          _uid = user_id.to_s
          adj = @adjacency[trace_id.to_s] || {}
          [adj[:prev], adj[:next]]
        end

        def all_entity_keys(user_id)
          uid = user_id.to_s
          @entities.select { |(u, _), _| u == uid }.map { |(_, key), _| key }
        end

        def store_turn_embedding(user_id, trace_id, vector, model:, dimensions:)
          @turn_embeddings[[user_id.to_s, trace_id.to_s]] = {
            vector: vector,
            model: model,
            dimensions: dimensions
          }
        end

        def search_traces_by_tokens(user_id, query, limit: 20)
          tokens = Llmemory::Tokenizer.tokenize(query)
          return [] if tokens.empty?

          list = list_traces(user_id)
          matched = list.select do |t|
            down = t.content.downcase
            tokens.all? { |tok| down.include?(tok) }
          end
          limit.to_i.positive? ? matched.first(limit.to_i) : matched
        end

        def reset_state!
          @traces = {}
          @idempotency = {}
          @sequences = Hash.new(0)
          @state_links = []
          @watermarks = {}
          @units = {}
          @open_episodes = {}
          @entities = {}
          @mentions = []
          @entity_traces = Hash.new { |h, k| h[k] = [] }
          @trace_entity_keys = Hash.new { |h, k| h[k] = [] }
          @adjacency = {}
          @turn_embeddings = {}
        end

        private

        def cascade_archive_derivatives(user_id, trace_id)
          uid = user_id.to_s
          tid = trace_id.to_s
          @mentions.reject! { |m| m.user_id == uid && m.trace_id == tid }
          @trace_entity_keys.delete([uid, tid])
          @entity_traces.each_value { |ids| ids.delete(tid) }
          @turn_embeddings.delete([uid, tid])
          @adjacency.delete(tid)
          @adjacency.each_value do |adj|
            adj.delete(:prev) if adj[:prev] == tid
            adj.delete(:next) if adj[:next] == tid
          end
        end

        def unit_references_archived_trace?(unit)
          unit.member_trace_ids.any? { |tid| !active_trace?(unit.user_id, tid) }
        end

        def active_trace?(user_id, trace_id)
          t = get_trace(user_id, trace_id)
          t&.active?
        end

        def idempotency_key(user_id, key)
          return nil if key.nil? || key.to_s.empty?

          [user_id.to_s, key.to_s]
        end
      end
    end
  end
end
