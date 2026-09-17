# frozen_string_literal: true

require "digest"

module Llmemory
  module ZeroMem
    class Backfill
      WARNING = "Backfill only covers messages still present in the checkpoint; " \
                "text removed by prior LLM compaction cannot be reconstructed."

      def initialize(storage:, indexer: nil)
        @storage = storage
        @indexer = indexer || Indexer.new(storage)
      end

      def run!(user_id:, session_id:, messages:, id_prefix: "backfill")
        created = []
        Array(messages).each_with_index do |msg, idx|
          role = msg[:role] || msg["role"]
          content = msg[:content] || msg["content"]
          next if content.to_s.empty?

          sequence = @storage.next_sequence(user_id, session_id)
          trace = Trace.build(
            user_id: user_id,
            session_id: session_id,
            role: role,
            content: content,
            sequence: sequence,
            idempotency_key: "#{id_prefix}-#{idx}-#{Digest::SHA256.hexdigest(content.to_s)[0, 12]}"
          )
          next if @storage.find_by_idempotency_key(user_id, trace.idempotency_key)

          @storage.write_trace(trace)
          @indexer.after_trace_write(trace: trace)
          created << trace.id
        end

        { created_trace_ids: created, warning: WARNING }
      end
    end
  end
end
