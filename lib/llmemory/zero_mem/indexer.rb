# frozen_string_literal: true

module Llmemory
  module ZeroMem
    # Index watermark + hierarchical units + entity graph (ZM2/ZM3).
    class Indexer
      def initialize(storage, mode: nil, builder: nil, entity_index: nil, embedding_provider: nil)
        @storage = storage
        @mode = (mode || Llmemory.configuration.zero_mem_index_mode).to_sym
        @builder = builder || HierarchyBuilder.new(storage)
        @entity_index = entity_index || EntityIndex.new(storage)
        @embedding_provider = embedding_provider
      end

      def after_trace_write(trace:, state_link: false)
        wm = @storage.get_watermark(trace.user_id, trace.session_id)
        next_version = wm[:index_version].to_i + 1
        affected_units = @builder.index_trace(trace, index_version: next_version)
        entity_stats = @entity_index.index_trace(trace)
        encoder_stats = index_embedding(trace)

        @storage.set_watermark(
          trace.user_id,
          trace.session_id,
          last_sequence: trace.sequence,
          index_version: next_version
        )

        {
          index_mode: @mode,
          index_lag: @mode == :deferred,
          affected_units: affected_units,
          affected_entities: entity_stats[:affected_entities],
          cache_invalidations: entity_stats[:cache_invalidations],
          maintenance_fanout: (state_link ? 2 : 1) + affected_units + entity_stats[:affected_entities],
          encoder_calls: encoder_stats[:encoder_calls],
          encoder_duration_ms: encoder_stats[:encoder_duration_ms]
        }
      end

      private

      def index_embedding(trace)
        provider = @embedding_provider || configured_embedding_provider
        return { encoder_calls: 0, encoder_duration_ms: 0.0 } unless provider

        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        vector = provider.embed_one(trace.content)
        elapsed = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round(2)
        @storage.store_turn_embedding(
          trace.user_id,
          trace.id,
          vector,
          model: provider.model,
          dimensions: provider.dimensions
        )
        Llmemory::Instrumentation.instrument(
          :encoder_embed,
          user_id: trace.user_id,
          trace_id: trace.id,
          model: provider.model,
          dimensions: provider.dimensions,
          duration_ms: elapsed
        )
        { encoder_calls: 1, encoder_duration_ms: elapsed }
      end

      def configured_embedding_provider
        Llmemory.configuration.zero_mem_embedding_provider
      end
    end
  end
end
