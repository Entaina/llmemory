# frozen_string_literal: true

RSpec.describe "Zero-Mem encoder metrics" do
  let(:storage) { Llmemory::ZeroMem::Storages::Memory.new }
  let(:provider) { Llmemory::ZeroMem::FakeEmbeddingProvider.new(dimensions: 8) }

  it "indexes embeddings without generative invoke" do
    indexer = Llmemory::ZeroMem::Indexer.new(storage, embedding_provider: provider)
    trace = Llmemory::ZeroMem::Trace.build(
      user_id: "u",
      session_id: "s",
      role: :user,
      content: "encoder test",
      sequence: 1
    )
    storage.write_trace(trace)
    stats = indexer.after_trace_write(trace: trace)
    expect(stats[:encoder_calls]).to eq(1)
    expect(provider.calls).to eq(1)
  end
end
