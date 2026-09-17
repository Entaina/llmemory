# frozen_string_literal: true

module Llmemory
  module ZeroMem
    module Storages
      module SnapshotCodec
        VERSION = 1

        module_function

        def dump(store)
          {
            version: VERSION,
            traces: store.instance_variable_get(:@traces).transform_values(&:to_h),
            idempotency: encode_tuple_keys(store.instance_variable_get(:@idempotency)),
            sequences: encode_tuple_keys(store.instance_variable_get(:@sequences)),
            state_links: store.instance_variable_get(:@state_links).map(&:to_h),
            watermarks: encode_tuple_keys(store.instance_variable_get(:@watermarks)),
            units: store.instance_variable_get(:@units).transform_values { |u| unit_to_h(u) },
            open_episodes: encode_tuple_keys(store.instance_variable_get(:@open_episodes)),
            entities: encode_tuple_keys(
              store.instance_variable_get(:@entities).transform_values { |e| entity_to_h(e) }
            ),
            mentions: store.instance_variable_get(:@mentions).map { |m| mention_to_h(m) },
            entity_traces: encode_tuple_keys(store.instance_variable_get(:@entity_traces)),
            trace_entity_keys: encode_tuple_keys(store.instance_variable_get(:@trace_entity_keys)),
            adjacency: store.instance_variable_get(:@adjacency),
            turn_embeddings: encode_tuple_keys(store.instance_variable_get(:@turn_embeddings))
          }
        end

        def encode_tuple_keys(hash)
          hash.each_with_object({}) do |(key, value), acc|
            encoded = key.is_a?(Array) ? key.join("|") : key.to_s
            acc[encoded] = value
          end
        end

        def decode_tuple_keys(hash, default_factory: nil)
          out = default_factory ? Hash.new { |h, k| h[k] = default_factory.call } : {}
          hash.each do |key, value|
            parts = key.to_s.split("|", 2)
            out_key = parts.size == 2 ? [parts[0], parts[1]] : key
            out[out_key] = value
          end
          out
        end

        def load!(store, data)
          store.send(:reset_state!)
          data = data.transform_keys(&:to_sym)
          traces_h = data[:traces]
          trace_rows = traces_h.is_a?(Hash) ? traces_h.values : Array(traces_h)
          trace_rows.each do |h|
            trace = Trace.new(**symbolize_times(h))
            store.instance_variable_get(:@traces)[trace.id] = trace
          end
          store.instance_variable_set(:@idempotency, decode_tuple_keys(data[:idempotency] || {}))
          sequences = decode_tuple_keys(data[:sequences] || {})
          sequences.default = 0
          store.instance_variable_set(:@sequences, sequences)
          store.instance_variable_set(:@state_links, Array(data[:state_links]).map { |h| TraceStateLink.new(**symbolize_times(h)) })
          store.instance_variable_set(:@watermarks, decode_tuple_keys(data[:watermarks] || {}))
          units_h = data[:units]
          unit_rows = units_h.is_a?(Hash) ? units_h.values : Array(units_h)
          unit_rows.each do |h|
            unit = unit_from_h(h)
            store.instance_variable_get(:@units)[unit.id] = unit
          end
          store.instance_variable_set(:@open_episodes, decode_tuple_keys(data[:open_episodes] || {}))
          decode_tuple_keys(data[:entities] || {}).each_value do |h|
            ent = entity_from_h(h)
            store.instance_variable_get(:@entities)[[ent.user_id, ent.normalized_key]] = ent
          end
          store.instance_variable_set(:@mentions, Array(data[:mentions]).map { |h| mention_from_h(h) })
          store.instance_variable_set(
            :@entity_traces,
            decode_tuple_keys(data[:entity_traces] || {}, default_factory: -> { [] })
          )
          store.instance_variable_get(:@entity_traces).default_proc = proc { |h, k| h[k] = [] }
          store.instance_variable_set(
            :@trace_entity_keys,
            decode_tuple_keys(data[:trace_entity_keys] || {}, default_factory: -> { [] })
          )
          store.instance_variable_get(:@trace_entity_keys).default_proc = proc { |h, k| h[k] = [] }
          store.instance_variable_set(:@adjacency, data[:adjacency] || {})
          store.instance_variable_set(:@turn_embeddings, decode_tuple_keys(data[:turn_embeddings] || {}))
          store
        end

        def unit_to_h(unit)
          {
            id: unit.id,
            user_id: unit.user_id,
            kind: unit.kind,
            session_id: unit.session_id,
            boundary_id: unit.boundary_id,
            start_sequence: unit.start_sequence,
            end_sequence: unit.end_sequence,
            occurred_from: unit.occurred_from.utc.iso8601(6),
            occurred_to: unit.occurred_to.utc.iso8601(6),
            member_trace_ids: unit.member_trace_ids,
            embedding_ref: unit.embedding_ref,
            index_version: unit.index_version
          }
        end

        def unit_from_h(h)
          h = symbolize_times(h)
          TraceUnit.new(
            id: h[:id],
            user_id: h[:user_id],
            kind: h[:kind].to_sym,
            session_id: h[:session_id],
            boundary_id: h[:boundary_id],
            start_sequence: h[:start_sequence],
            end_sequence: h[:end_sequence],
            occurred_from: h[:occurred_from],
            occurred_to: h[:occurred_to],
            member_trace_ids: h[:member_trace_ids] || [],
            embedding_ref: h[:embedding_ref],
            index_version: h[:index_version] || 0
          )
        end

        def entity_to_h(entity)
          {
            id: entity.id,
            user_id: entity.user_id,
            normalized_key: entity.normalized_key,
            display_name: entity.display_name,
            entity_type: entity.entity_type,
            ambiguous: entity.ambiguous
          }
        end

        def entity_from_h(h)
          h = h.transform_keys(&:to_sym)
          Entity.new(
            id: h[:id],
            user_id: h[:user_id],
            normalized_key: h[:normalized_key],
            display_name: h[:display_name],
            entity_type: (h[:entity_type] || :entity).to_sym,
            ambiguous: h[:ambiguous] || false
          )
        end

        def mention_to_h(mention)
          {
            id: mention.id,
            user_id: mention.user_id,
            trace_id: mention.trace_id,
            entity_id: mention.entity_id,
            normalized_key: mention.normalized_key,
            text: mention.text,
            offset_start: mention.offset_start,
            offset_end: mention.offset_end
          }
        end

        def mention_from_h(h)
          EntityMention.new(**h.transform_keys(&:to_sym))
        end

        def symbolize_times(h)
          out = h.transform_keys(&:to_sym)
          %i[occurred_at ingested_at archived_at valid_from valid_to created_at occurred_from occurred_to].each do |key|
            next unless out[key]

            out[key] = Time.parse(out[key].to_s) unless out[key].is_a?(Time)
          end
          out[:role] = out[:role].to_sym if out[:role]
          out[:source] = out[:source].to_sym if out[:source]
          out
        end
      end
    end
  end
end
