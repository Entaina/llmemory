# frozen_string_literal: true

module Llmemory
  module ZeroMem
    class EntityIndex
      def initialize(storage, extractor: nil)
        @storage = storage
        @extractor = extractor || build_extractor
      end

      def extract_entities(text)
        @extractor.extract(text)
      end

      def index_trace(trace)
        entities_touched = 0
        mentions = @extractor.extract(trace.content)
        keys = []

        mentions.each do |m|
          entity = Entity.build(
            user_id: trace.user_id,
            normalized_key: m[:normalized],
            display_name: m[:text]
          )
          @storage.upsert_entity(entity)
          mention = EntityMention.build(
            user_id: trace.user_id,
            trace_id: trace.id,
            entity_id: entity.id,
            normalized_key: entity.normalized_key,
            text: m[:text],
            offset_start: m[:start],
            offset_end: m[:end]
          )
          @storage.write_mention(mention)
          keys << entity.normalized_key
          entities_touched += 1
        end

        prev = @storage.previous_trace(trace.user_id, trace.session_id, trace.sequence)
        if prev
          @storage.link_adjacent_traces(trace.user_id, prev.id, trace.id)
        end

        {
          affected_entities: entities_touched,
          entity_keys: keys.uniq,
          cache_invalidations: entities_touched
        }
      end

      private

      def build_extractor
        case Llmemory.configuration.zero_mem_entity_extractor.to_sym
        when :http
          Extractors::Http.new(base_url: Llmemory.configuration.zero_mem_ner_http_url)
        else
          Extractors::Heuristic.new
        end
      end
    end
  end
end
