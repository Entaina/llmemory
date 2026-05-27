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
      allow(vector_store_double).to receive(:search_by_text).with("work", top_k: 20, user_id: user_id)
        .and_return([{ id: "e1", score: 0.85, metadata: { "text" => "User works_at Acme" } }])
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

  describe "#forget" do
    it "is not supported yet and fails explicitly" do
      expect { memory.forget(ids: ["edge_1"]) }.to raise_error(NotImplementedError, /Graph forget/)
    end
  end
end
