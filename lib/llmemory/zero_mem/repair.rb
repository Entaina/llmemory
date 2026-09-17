# frozen_string_literal: true

module Llmemory
  module ZeroMem
    class Repair
      def initialize(storage:)
        @storage = storage
      end

      # Reconcile watermark with persisted traces and checkpoint message counts (ZM1).
      def run!(user_id:, session_id:, checkpoint_messages:)
        traces = @storage.list_traces(user_id, session_id: session_id)
        last_sequence = traces.map(&:sequence).max.to_i
        wm = @storage.get_watermark(user_id, session_id)
        @storage.set_watermark(
          user_id,
          session_id,
          last_sequence: last_sequence,
          index_version: [wm[:index_version].to_i, last_sequence].max
        )

        {
          trace_count: traces.size,
          checkpoint_message_count: Array(checkpoint_messages).size,
          last_sequence: last_sequence,
          index_version: [wm[:index_version].to_i, last_sequence].max
        }
      end
    end
  end
end
