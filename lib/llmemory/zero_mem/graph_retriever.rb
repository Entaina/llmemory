# frozen_string_literal: true

module Llmemory
  module ZeroMem
    class GraphRetriever
      MAX_NODES = 200

      def initialize(storage, entity_index: nil, embedding_provider: nil, config: Llmemory.configuration)
        @storage = storage
        @entity_index = entity_index || EntityIndex.new(storage)
        @embedding_provider = embedding_provider
        @config = config
        @pagerank = PageRank.new(gamma: config.zero_mem_pagerank_damping)
      end

      def retrieve(user_id:, query:, profile:, top_k:)
        warnings = []
        degraded = []
        query_entities = @entity_index.extract_entities(query)
        degraded << :ner if query_entities.empty?

        seeds = match_entities(user_id, query, query_entities, degraded: degraded)
        return empty_result(degraded, warnings) if seeds.empty?

        trace_ids = seeds.flat_map { |key| @storage.trace_ids_for_entity_key(user_id, key) }.uniq
        trace_ids = trace_ids.first(MAX_NODES)
        warnings << :pagerank_truncated if trace_ids.size >= MAX_NODES

        graph, reset = build_graph(user_id, trace_ids, seeds)
        ranks = @pagerank.run(graph, reset)
        trace_scores = ranks.select { |node, _| node.start_with?("tr:") }
                            .transform_keys { |k| k.sub("tr:", "") }
        trace_ids.each { |tid| trace_scores[tid] ||= 0.5 }
        trace_scores = trace_scores.sort_by { |_, score| -score }

        traces = trace_scores.first(top_k).map do |trace_id, score|
          t = @storage.get_trace(user_id, trace_id)
          next unless t

          { trace: t, score: score }
        end.compact

        {
          traces: traces.map { |h| h[:trace] },
          trace_scores: trace_scores.to_h,
          degraded: degraded.uniq,
          warnings: warnings
        }
      end

      private

      def empty_result(degraded, warnings)
        { traces: [], trace_scores: {}, degraded: degraded.uniq, warnings: warnings }
      end

      def match_entities(user_id, query, query_entities, degraded:)
        keys = query_entities.map { |e| e[:normalized] }.compact
        tokens = Llmemory::Tokenizer.tokenize(query)
        keys = expand_entity_keys(user_id, keys) if keys.any?
        if keys.empty?
          keys = @storage.all_entity_keys(user_id).select do |key|
            tokens.any? { |t| key.include?(t) || t.include?(key) }
          end
        end
        degraded << :dense if @embedding_provider.nil?
        keys.select { |k| @storage.entity_exists?(user_id, k) }
      end

      def expand_entity_keys(user_id, keys)
        stored = @storage.all_entity_keys(user_id)
        keys.flat_map do |k|
          next [] if k.to_s.length < 2

          stored.select { |s| s == k || s.include?(k) || k.include?(s) }
        end.uniq
      end

      def build_graph(user_id, trace_ids, seed_keys)
        graph = {}
        reset = {}

        trace_ids.each do |tid|
          node = "tr:#{tid}"
          neighbors = ["tr:#{tid}"]
          @storage.entity_keys_for_trace(user_id, tid).each do |key|
            ent_node = "ent:#{key}"
            graph[ent_node] ||= []
            graph[ent_node] << node
            graph[node] ||= []
            graph[node] << ent_node
            neighbors << ent_node
            reset[ent_node] = 1.0 if seed_keys.include?(key)
          end
          prev, nxt = @storage.adjacent_traces(user_id, tid)
          [prev, nxt].compact.each do |other|
            graph[node] ||= []
            graph[node] << "tr:#{other}"
          end
          graph[node] = (graph[node] || neighbors).uniq
        end

        [graph, reset]
      end
    end
  end
end
