# frozen_string_literal: true

RSpec.describe Llmemory::ZeroMem::FakeEmbeddingProvider do
  it "returns stable vectors with declared dimensions" do
    provider = described_class.new(dimensions: 16)
    a = provider.embed(%w[hello hello world])
    expect(a.size).to eq(3)
    expect(a[0]).to eq(a[1])
    expect(a[0].size).to eq(16)
    expect(provider.local?).to be(true)
  end
end
