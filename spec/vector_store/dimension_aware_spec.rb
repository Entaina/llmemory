# frozen_string_literal: true

RSpec.describe "dimension-aware vector store" do
  it "rejects mismatched embedding sizes" do
    provider = Llmemory::ZeroMem::FakeEmbeddingProvider.new(dimensions: 8)
    store = Llmemory::VectorStore::MemoryStore.new(embedding_provider: provider)
    vec8 = provider.embed_one("hello")
    store.store(id: "a", embedding: vec8, user_id: "u1")
    expect {
      store.search(Array.new(16, 0.1), user_id: "u1")
    }.to raise_error(Llmemory::ConfigurationError, /dimension mismatch/)
  end

  it "allows different providers with different dimensions in separate stores" do
    p8 = Llmemory::ZeroMem::FakeEmbeddingProvider.new(dimensions: 8)
    p16 = Llmemory::ZeroMem::FakeEmbeddingProvider.new(dimensions: 16)
    s8 = Llmemory::VectorStore::MemoryStore.new(embedding_provider: p8)
    s16 = Llmemory::VectorStore::MemoryStore.new(embedding_provider: p16)
    s8.store(id: "a", embedding: p8.embed_one("a"), user_id: "u")
    s16.store(id: "b", embedding: p16.embed_one("b"), user_id: "u")
    expect(s8.search(p8.embed_one("a"), user_id: "u").first[:id]).to eq("a")
  end
end
