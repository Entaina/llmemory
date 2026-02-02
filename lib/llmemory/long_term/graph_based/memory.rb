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
          data = @extractor.extract(conversation_text) rescue { entities: [], relations: [] }
          data = { entities: [], relations: [] } unless data.is_a?(Hash)
          entities = Array(data[:entities] || data["entities"])
          relations = Array(data[:relations] || data["relations"])

          return true if entities.empty? && relations.empty?

          name_to_id = {}

          entities.each do |e|
            next unless e.is_a?(Hash)
            entity_type = e[:type] || e["type"] || "concept"
            name = e[:name] || e["name"]
            next if name.nil? || name.to_s.strip.empty?
            id = @kg.add_node(entity_type: entity_type, name: name.to_s.strip, properties: {})
            name_to_id[name.to_s.strip] ||= id
          end

          relations.each do |r|
            next unless r.is_a?(Hash)
            subject = (r[:subject] || r["subject"]).to_s.strip
            predicate = (r[:predicate] || r["predicate"]).to_s.strip
            object = (r[:object] || r["object"]).to_s.strip
            next if subject.empty? || predicate.empty? || object.empty?

            subject_id = name_to_id[subject] || @kg.add_node(entity_type: "concept", name: subject, properties: {})
            object_id = name_to_id[object] || @kg.add_node(entity_type: "concept", name: object, properties: {})

            edge = Edge.new(
              id: nil,
              user_id: @user_id,
              subject_id: subject_id,
              predicate: predicate,
              target_id: object_id,
              properties: {},
              created_at: Time.now,
              archived_at: nil
            )
            @conflict_resolver.resolve(edge)
            edge_id = @kg.add_edge(subject: subject_id, predicate: predicate, object: object_id, properties: {})

            text = "#{subject} #{predicate} #{object}"
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
          store_type = (Llmemory.configuration.long_term_store || :memory).to_s.to_sym
          if store_type == :active_record || store_type == :activerecord
            require_relative "../../vector_store/active_record_store"
            Llmemory::VectorStore::ActiveRecordStore.new(embedding_provider: emb)
          else
            Llmemory::VectorStore::MemoryStore.new(embedding_provider: emb)
          end
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
              obj = @kg.find_node_by_id(e.target_id)
              edge_text = "#{subj&.name} #{e.predicate} #{obj&.name}"
              out << { text: edge_text, score: 0.85, created_at: e.created_at } unless out.any? { |o| o[:text] == edge_text }
            end
          end

          # When vector store is empty (e.g. in-memory not persisted), use graph edges as fallback
          # so long-term context is still recovered from persisted nodes/edges.
          if out.empty? && @graph_storage.respond_to?(:list_edges)
            edges = @graph_storage.list_edges(@user_id, limit: top_k)
            edges.each do |e|
              subj = @kg.find_node_by_id(e.subject_id)
              obj = @kg.find_node_by_id(e.target_id)
              next unless subj && obj
              edge_text = "#{subj.name} #{e.predicate} #{obj.name}"
              out << { text: edge_text, score: 0.7, created_at: e.created_at }
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
