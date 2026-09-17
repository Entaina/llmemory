# frozen_string_literal: true

module Llmemory
  module ZeroMem
    class HierarchyBuilder
      def initialize(storage, config: Llmemory.configuration)
        @storage = storage
        @config = config
      end

      def index_trace(trace, index_version:)
        affected = 0
        affected += write_turn_unit(trace, index_version)
        affected += update_tail_windows(trace, index_version)
        affected += update_episode(trace, index_version)
        affected
      end

      private

      def window_size
        @config.zero_mem_window_size.to_i.positive? ? @config.zero_mem_window_size.to_i : 8
      end

      def window_overlap
        ov = @config.zero_mem_window_overlap.to_i
        ov = 2 if ov.negative?
        [ov, window_size - 1].min
      end

      def episode_gap_seconds
        gap = @config.zero_mem_episode_gap_seconds.to_i
        gap.positive? ? gap : 86_400
      end

      def write_turn_unit(trace, index_version)
        unit = TraceUnit.build(
          id: "turn_#{trace.id}",
          user_id: trace.user_id,
          kind: :turn,
          session_id: trace.session_id,
          boundary_id: trace.boundary_id,
          start_sequence: trace.sequence,
          end_sequence: trace.sequence,
          occurred_from: trace.occurred_at,
          occurred_to: trace.occurred_at,
          member_trace_ids: [trace.id],
          index_version: index_version
        )
        @storage.write_unit(unit)
        1
      end

      def update_tail_windows(trace, index_version)
        size = window_size
        seq = trace.sequence
        start_seq = [1, seq - size + 1].max
        traces = @storage.list_traces(trace.user_id, session_id: trace.session_id).select do |t|
          t.sequence >= start_seq && t.sequence <= seq
        end
        return 0 if traces.empty?

        unit = TraceUnit.build(
          id: "window_#{trace.session_id}_#{traces.first.sequence}_#{traces.last.sequence}",
          user_id: trace.user_id,
          kind: :window,
          session_id: trace.session_id,
          boundary_id: trace.boundary_id,
          start_sequence: traces.first.sequence,
          end_sequence: traces.last.sequence,
          occurred_from: traces.first.occurred_at,
          occurred_to: traces.last.occurred_at,
          member_trace_ids: traces.map(&:id),
          index_version: index_version
        )
        @storage.write_unit(unit)
        1
      end

      def update_episode(trace, index_version)
        key = trace.boundary_id || trace.session_id
        open_episode = @storage.open_episode(trace.user_id, key)
        gap = episode_gap_seconds

        if open_episode
          last_at = open_episode.occurred_to
          if (trace.occurred_at - last_at).to_f > gap
            @storage.close_episode(open_episode.id)
            open_episode = nil
          end
        end

        if open_episode
          ids = (open_episode.member_trace_ids + [trace.id]).uniq
          traces = ids.map { |id| @storage.get_trace(trace.user_id, id) }.compact
          updated = open_episode.with(
            end_sequence: trace.sequence,
            occurred_to: trace.occurred_at,
            member_trace_ids: ids,
            index_version: index_version
          )
          @storage.write_unit(updated)
        else
          unit = TraceUnit.build(
            user_id: trace.user_id,
            kind: :episode,
            session_id: trace.session_id,
            boundary_id: trace.boundary_id,
            start_sequence: trace.sequence,
            end_sequence: trace.sequence,
            occurred_from: trace.occurred_at,
            occurred_to: trace.occurred_at,
            member_trace_ids: [trace.id],
            index_version: index_version
          )
          @storage.write_unit(unit)
          @storage.set_open_episode(trace.user_id, key, unit.id)
        end
        1
      end
    end
  end
end
