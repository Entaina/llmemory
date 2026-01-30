# frozen_string_literal: true

require_relative "node"
require_relative "edge"
require_relative "knowledge_graph"
require_relative "conflict_resolver"
require_relative "storage"

module Llmemory
  module LongTerm
    module GraphBased
      class Memory
        def initialize(user_id:, storage: nil, vector_store: nil, llm: nil, extractor: nil)
          @user_id = user_id
          @graph_storage = storage || Storages.build
          @kg = KnowledgeGraph.new(user_id: user_id, storage: @graph_storage)
          @conflict_resolver = ConflictResolver.new(@kg)
          @vector_store = vector_store || build_vector_store
          @llm = llm || Llmemory::LLM.client
          @extractor = extractor || Llmemory::Extractors::EntityRelationExtractor.new(llm: @llm)
        end

        def memorize(conversation_text)
          data = @extractor.extract(conversation_text)
          name_to_id = {}

          data[:entities].each do |e|
            id = @kg.add_node(entity_type: e[:type], name: e[:name], properties: {})
            name_to_id[e[:name]] ||= id
          end

          data[:relations].each do |r|
            subject_id = name_to_id[r[:subject]] || @kg.add_node(entity_type: "concept", name: r[:subject], properties: {})
            object_id = name_to_id[r[:object]] || @kg.add_node(entity_type: "concept", name: r[:object], properties: {})

            edge = Edge.new(
              id: nil,
              user_id: @user_id,
              subject_id: subject_id,
              predicate: r[:predicate],
              object_id: object_id,
              properties: {},
              created_at: Time.now,
              archived_at: nil
            )
            @conflict_resolver.resolve(edge)
            edge_id = @kg.add_edge(subject: subject_id, predicate: r[:predicate], object: object_id, properties: {})

            text = "#{r[:subject]} #{r[:predicate]} #{r[:object]}"
            embedding = @vector_store.respond_to?(:embed) ? @vector_store.embed(text) : nil
            if embedding && @vector_store.respond_to?(:store)
              @vector_store.store(id: "edge_#{edge_id}", embedding: embedding, metadata: { text: text, created_at: Time.now }, user_id: @user_id)
            end
          end

          true
        end

        def retrieve(query, top_k: 10)
          results = hybrid_search(query, top_k: top_k)
          format_as_context(results)
        end

        def search_candidates(query, user_id: nil, top_k: 20)
          uid = user_id || @user_id
          return [] unless uid == @user_id
          results = hybrid_search(query, top_k: top_k)
          results.map do |r|
            {
              text: r[:text],
              timestamp: r[:created_at] || r[:timestamp],
              score: r[:score] || 1.0
            }
          end
        end

        attr_reader :user_id

        def storage
          @graph_storage
        end

        private

        def build_vector_store
          emb = Llmemory::VectorStore::OpenAIEmbeddings.new
          Llmemory::VectorStore::MemoryStore.new(embedding_provider: emb)
        end

        def hybrid_search(query, top_k:)
          vector_results = []
          if @vector_store.respond_to?(:search_by_text)
            vector_results = @vector_store.search_by_text(query.to_s, top_k: top_k, user_id: @user_id)
          elsif @vector_store.respond_to?(:embed) && @vector_store.respond_to?(:search)
            emb = @vector_store.embed(query.to_s)
            vector_results = @vector_store.search(emb, top_k: top_k, user_id: @user_id)
          end

          out = vector_results.map do |v|
            id = v[:id] || v["id"]
            meta = v[:metadata] || v["metadata"] || {}
            { text: meta["text"] || meta[:text] || id.to_s, score: v[:score] || v["score"] || 1.0, created_at: meta["created_at"] || meta[:created_at] }
          end

          node_ids = out.flat_map { |r| extract_node_ids_from_text(r[:text]) }.compact.uniq
          node_ids.first(3).each do |node_id|
            node = @kg.find_node_by_id(node_id)
            next unless node
            traversed = @kg.traverse(start_node: node, depth: 1)
            traversed[:edges].each do |e|
              subj = @kg.find_node_by_id(e.subject_id)
              obj = @kg.find_node_by_id(e.object_id)
              edge_text = "#{subj&.name} #{e.predicate} #{obj&.name}"
              out << { text: edge_text, score: 0.85, created_at: e.created_at } unless out.any? { |o| o[:text] == edge_text }
            end
          end

          out.sort_by { |r| -(r[:score] || 0) }.first(top_k)
        end

        def extract_node_ids_from_text(text)
          return [] if text.to_s.empty?
          ids = []
          @kg.list_nodes.each do |n|
            ids << n.id if text.to_s.include?(n.name.to_s)
          end
          ids
        end

        def format_as_context(results)
          return "" if results.empty?
          lines = ["=== RELEVANT MEMORIES (GRAPH) ===", ""]
          results.each do |r|
            lines << "- #{r[:text]}"
          end
          lines << ""
          lines << "=== END MEMORIES ==="
          lines.join("\n")
        end
      end
    end
  end
end
