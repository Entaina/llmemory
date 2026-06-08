# frozen_string_literal: true

require_relative "node"
require_relative "edge"
require_relative "knowledge_graph"
require_relative "conflict_resolver"
require_relative "storage"
require_relative "../../noise_filter"
require_relative "../../memory_module"

module Llmemory
  module LongTerm
    module GraphBased
      class Memory
        include Llmemory::MemoryModule

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
          text = Llmemory.configuration.noise_filter_enabled ? NoiseFilter.filter?(conversation_text) : conversation_text.to_s
          return true if text.strip.empty?

          entities, relations = extract_graph(text)
          return true if entities.empty? && relations.empty?

          provenance = Llmemory::Provenance.from_text_fingerprint(text, method: "entity_relation_extraction")
          ingest(entities, relations, provenance)
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
              id: r[:id],
              text: r[:text],
              timestamp: r[:created_at] || r[:timestamp],
              score: r[:score] || 1.0,
              importance: r[:importance]
            }
          end
        end

        attr_reader :user_id

        def storage
          @graph_storage
        end

        # Stores a fact produced outside the conversational flow (e.g. a
        # reflection insight) by extracting entities/relations from `content` and
        # adding them to the graph, preserving caller-supplied provenance. Lets
        # the Reflector target graph-based semantic memory.
        def remember_fact(content:, category: nil, importance: nil, provenance: nil)
          return nil if content.to_s.strip.empty?
          entities, relations = extract_graph(content)
          return nil if entities.empty? && relations.empty?
          prov = provenance || Llmemory::Provenance.from_text_fingerprint(content, method: "reflection")
          ingest(entities, relations, prov)
          true
        end

        # --- MemoryModule uniform interface ---

        def write(payload, **_meta)
          result = nil
          Llmemory::Instrumentation.instrument(:memory_write, memory_type: "graph_based", user_id: @user_id) do
            result = memorize(payload)
          end
          result
        end

        def list(user_id: nil, limit: nil, offset: nil)
          @graph_storage.list_nodes(user_id || @user_id, limit: limit, offset: offset)
        end

        def stats(user_id: nil)
          uid = user_id || @user_id
          { nodes: @graph_storage.count_nodes(uid), edges: @graph_storage.count_edges(uid) }
        end

        # Forgets relations by archiving the edges identified by the candidate
        # ids returned from #read/#search_candidates (edge ids), recording the
        # removal in the audit log. Edges are soft-archived (archived_at) so they
        # no longer appear in retrieval; nodes are left in place (a node may still
        # be referenced by other active edges). Returns the number archived.
        def forget(ids:, reason: nil, mode: :soft)
          # `:hard` would physically delete edge rows; not yet wired (the graph
          # store only exposes soft archive_edge). Both modes route to archive
          # for now; behavior is the same — kept for API uniformity.
          archived = Array(ids).map(&:to_s).select { |edge_id| @kg.archive_edge(edge_id) }
          forget_log.record(@user_id, memory_type: "graph_based", ids: archived, reason: reason)
          Llmemory::Instrumentation.instrument(:memory_forget, memory_type: "graph_based", user_id: @user_id, count: archived.size, mode: mode)
          archived.size
        end

        private

        def build_vector_store
          Llmemory::VectorStore.build(source_type: "edge")
        end

        def extract_graph(text)
          data = @extractor.extract(text) rescue { entities: [], relations: [] }
          data = { entities: [], relations: [] } unless data.is_a?(Hash)
          [Array(data[:entities] || data["entities"]), Array(data[:relations] || data["relations"])]
        end

        # Adds entities and relations to the graph (nodes, edges, embeddings) with
        # the given provenance. Shared by memorize (conversation) and
        # remember_fact (reflection).
        def ingest(entities, relations, provenance)
          name_to_id = {}

          entities.each do |e|
            next unless e.is_a?(Hash)
            entity_type = e[:type] || e["type"] || "concept"
            name = e[:name] || e["name"]
            next if name.nil? || name.to_s.strip.empty?
            id = @kg.add_node(entity_type: entity_type, name: name.to_s.strip, properties: { "provenance" => provenance })
            name_to_id[name.to_s.strip] ||= id
          end

          relations.each do |r|
            next unless r.is_a?(Hash)
            subject = (r[:subject] || r["subject"]).to_s.strip
            predicate = (r[:predicate] || r["predicate"]).to_s.strip
            object = (r[:object] || r["object"]).to_s.strip
            next if subject.empty? || predicate.empty? || object.empty?

            subject_id = name_to_id[subject] || @kg.add_node(entity_type: "concept", name: subject, properties: { "provenance" => provenance })
            object_id = name_to_id[object] || @kg.add_node(entity_type: "concept", name: object, properties: { "provenance" => provenance })

            edge = Edge.new(
              id: nil,
              user_id: @user_id,
              subject_id: subject_id,
              predicate: predicate,
              target_id: object_id,
              properties: { "provenance" => provenance },
              created_at: Time.now,
              archived_at: nil
            )
            @conflict_resolver.resolve(edge)
            edge_id = @kg.add_edge(subject: subject_id, predicate: predicate, object: object_id, properties: { "provenance" => provenance })

            edge_text = "#{subject} #{predicate} #{object}"
            embedding = @vector_store.respond_to?(:embed) ? @vector_store.embed(edge_text) : nil
            if embedding && @vector_store.respond_to?(:store)
              @vector_store.store(id: edge_id, embedding: embedding, metadata: { text: edge_text, created_at: Time.now }, user_id: @user_id)
            end
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
            { id: id, text: meta["text"] || meta[:text] || id.to_s, score: v[:score] || v["score"] || 1.0, created_at: meta["created_at"] || meta[:created_at] }
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
              out << { id: e.id, text: edge_text, score: 0.85, created_at: e.created_at } unless out.any? { |o| o[:text] == edge_text }
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
              out << { id: e.id, text: edge_text, score: 0.7, created_at: e.created_at }
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
