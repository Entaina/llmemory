# frozen_string_literal: true

RSpec.describe Llmemory::VectorStore::MemoryStore do
  let(:embedding_provider) do
    double("EmbeddingProvider").tap do |d|
      allow(d).to receive(:embed).with("hello").and_return([0.1] * 1536)
      allow(d).to receive(:embed).with("world").and_return([0.2] * 1536)
      allow(d).to receive(:embed).with("query").and_return([0.15] * 1536)
    end
  end
  let(:store) { described_class.new(embedding_provider: embedding_provider) }

  describe "#store and #search" do
    it "stores embedding by id and finds by similarity" do
      store.store(id: "a", embedding: [0.1] * 1536, metadata: { "text" => "hello" })
      store.store(id: "b", embedding: [0.2] * 1536, metadata: { "text" => "world" }, user_id: "u1")
      results = store.search([0.15] * 1536, top_k: 2, user_id: "u1")
      expect(results).to be_an(Array)
      expect(results.size).to be <= 2
      expect(results.first).to include(:id, :score, :metadata)
    end

    it "scopes search by user_id when given" do
      store.store(id: "x", embedding: [0.1] * 1536, metadata: {}, user_id: "user_1")
      store.store(id: "y", embedding: [0.1] * 1536, metadata: {}, user_id: "user_2")
      results = store.search([0.1] * 1536, top_k: 5, user_id: "user_1")
      ids = results.map { |r| r[:id].to_s }
      expect(ids).to all(match(/^user_1:/))
    end
  end

  describe "#search_by_text" do
    it "embeds query and returns similar entries" do
      store.store(id: "t1", embedding: [0.1] * 1536, metadata: { "text" => "hello" })
      results = store.search_by_text("query", top_k: 5)
      expect(embedding_provider).to have_received(:embed).with("query")
      expect(results).to be_an(Array)
    end
  end

  describe "#embed" do
    it "delegates to embedding_provider" do
      vec = store.embed("hello")
      expect(vec).to eq([0.1] * 1536)
    end
  end
end
