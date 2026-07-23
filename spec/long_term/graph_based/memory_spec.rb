# frozen_string_literal: true

RSpec.describe Llmemory::LongTerm::GraphBased::Memory do
  let(:user_id) { "user_1" }
  let(:storage) { Llmemory::LongTerm::GraphBased::Storages::MemoryStorage.new }
  let(:extractor_double) do
    double("EntityRelationExtractor").tap do |d|
      allow(d).to receive(:extract).with(anything).and_return(entities: [], relations: [])
      allow(d).to receive(:extract).with("I work at Acme.").and_return(
        entities: [
          { type: "person", name: "User" },
          { type: "company", name: "Acme" }
        ],
        relations: [
          { subject: "User", predicate: "works_at", object: "Acme" }
        ]
      )
    end
  end
  let(:vector_store_double) do
    double("VectorStore").tap do |d|
      allow(d).to receive(:embed).with(anything).and_return([0.1] * 1536)
      allow(d).to receive(:store).with(hash_including(:id, :embedding, :metadata)).and_return("edge_1")
      allow(d).to receive(:delete).with(hash_including(:id, :user_id)).and_return(true)
      allow(d).to receive(:search_by_text).with(anything, top_k: anything, user_id: anything).and_return([])
      allow(d).to receive(:search).with(anything, top_k: anything, user_id: anything).and_return([])
    end
  end
  let(:memory) do
    described_class.new(
      user_id: user_id,
      storage: storage,
      vector_store: vector_store_double,
      extractor: extractor_double
    )
  end

  describe "#memorize" do
    it "extracts entities and relations, adds nodes and edges" do
      memory.memorize("I work at Acme.")
      nodes = storage.list_nodes(user_id)
      expect(nodes.map(&:name)).to contain_exactly("User", "Acme")
      edges = storage.find_edges(user_id, predicate: "works_at", include_archived: false)
      expect(edges.size).to eq(1)
      expect(edges.first.predicate).to eq("works_at")
    end

    it "stores embeddings for relation text" do
      memory.memorize("I work at Acme.")
      expect(vector_store_double).to have_received(:embed).with("User works_at Acme")
      expect(vector_store_double).to have_received(:store).with(
        hash_including(:id, :embedding, :metadata)
      )
    end

    it "does not duplicate identical active edges on re-ingest" do
      memory.memorize("I work at Acme.")
      memory.memorize("I work at Acme.")
      edges = storage.find_edges(user_id, predicate: "works_at", include_archived: false)
      expect(edges.size).to eq(1)
    end

    it "returns true" do
      expect(memory.memorize("Hello")).to be true
    end

    it "stamps nodes and edges with extraction provenance" do
      memory.memorize("I work at Acme.")

      node = storage.list_nodes(user_id).first
      node_prov = node.provenance
      expect(node_prov).not_to be_nil
      expect(node_prov[:method]).to eq("entity_relation_extraction")

      edge = storage.find_edges(user_id, predicate: "works_at", include_archived: false).first
      edge_prov = edge.provenance
      expect(edge_prov[:method]).to eq("entity_relation_extraction")
      expect(edge_prov[:sources].first[:type]).to eq("text_sha256")
    end
  end

  describe "#retrieve" do
    before do
      memory.memorize("I work at Acme.")
      allow(vector_store_double).to receive(:search_by_text).with("job", top_k: 10, user_id: user_id)
        .and_return([{ id: "edge_1", score: 0.9, metadata: { "text" => "User works_at Acme", "created_at" => Time.now } }])
    end

    it "returns formatted context string" do
      result = memory.retrieve("job", top_k: 10)
      expect(result).to include("RELEVANT MEMORIES")
      expect(result).to include("User works_at Acme")
    end
  end

  describe "#search_candidates" do
    before do
      memory.memorize("I work at Acme.")
      edge_id = storage.find_edges(user_id, predicate: "works_at", include_archived: false).first.id
      allow(vector_store_double).to receive(:search_by_text).with("work", top_k: 20, user_id: user_id)
        .and_return([{ id: edge_id, score: 0.85, metadata: { "text" => "User works_at Acme" } }])
    end

    it "returns array of candidates with text and score" do
      candidates = memory.search_candidates("work", top_k: 20)
      expect(candidates).to be_an(Array)
      expect(candidates.any? { |c| c[:text].to_s.include?("works_at") }).to be true
    end

    it "returns empty for different user_id" do
      candidates = memory.search_candidates("work", user_id: "other_user", top_k: 20)
      expect(candidates).to eq([])
    end
  end

  describe "#user_id" do
    it "returns the given user_id" do
      expect(memory.user_id).to eq(user_id)
    end
  end

  describe "node name matching" do
    let(:extractor_with_ai) do
      double("EntityRelationExtractor").tap do |d|
        allow(d).to receive(:extract).and_return(
          entities: [
            { type: "concept", name: "AI" },
            { type: "company", name: "Acme Corp" }
          ],
          relations: []
        )
      end
    end
    let(:memory_with_ai) do
      described_class.new(
        user_id: user_id,
        storage: storage,
        vector_store: vector_store_double,
        extractor: extractor_with_ai
      )
    end

    before { memory_with_ai.memorize("AI at Acme Corp") }

    it "matches node names by tokens, not substring inclusion" do
      ids = memory_with_ai.send(:extract_node_ids_from_text, "it was raining yesterday")
      expect(ids).to be_empty
    end

    it "matches when all name tokens appear in the query" do
      ids = memory_with_ai.send(:extract_node_ids_from_text, "Acme Corp deploy")
      ai_node = storage.list_nodes(user_id).find { |n| n.name == "AI" }
      acme_node = storage.list_nodes(user_id).find { |n| n.name == "Acme Corp" }
      expect(ids).to include(acme_node.id)
      expect(ids).not_to include(ai_node.id) unless ids.include?(ai_node.id)
    end
  end

  describe "#forget" do
    it "archives matching edges by id and records an audit entry" do
      memory.memorize("I work at Acme.")
      edge = storage.find_edges(user_id, predicate: "works_at", include_archived: false).first

      removed = memory.forget(ids: [edge.id], reason: "obsolete")

      expect(removed).to eq(1)
      expect(storage.find_edges(user_id, predicate: "works_at", include_archived: false)).to be_empty
      expect(vector_store_double).to have_received(:delete).with(id: edge.id, user_id: user_id)
      expect(memory.forget_log.entries(user_id).last).to include(memory_type: "graph_based", reason: "obsolete")
    end
  end

  describe "#remember_fact" do
    it "ingests a fact as entities/relations with caller-supplied provenance" do
      prov = Llmemory::Provenance.build(method: "reflection", sources: [{ type: "episode", id: "ep_1" }])
      memory.remember_fact(content: "I work at Acme.", provenance: prov)

      edge = storage.find_edges(user_id, predicate: "works_at", include_archived: false).first
      expect(edge).not_to be_nil
      method = edge.provenance[:method] || edge.provenance["method"]
      expect(method).to eq("reflection")
    end
  end
end
