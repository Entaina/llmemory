# frozen_string_literal: true

RSpec.describe Llmemory::Retrieval::FeedbackStore do
  let(:store) { described_class.new(store: Llmemory::ShortTerm::Stores::MemoryStore.new) }

  it "accumulates deltas per item" do
    store.record("u1", "item_1", 1)
    store.record("u1", "item_1", 1)
    store.record("u1", "item_1", -1)
    expect(store.net("u1", "item_1")).to eq(1)
  end

  it "returns 0 for items with no feedback" do
    expect(store.net("u1", "unknown")).to eq(0)
  end

  it "isolates feedback per user" do
    store.record("u1", "item_1", 1)
    expect(store.net("u2", "item_1")).to eq(0)
  end

  it "ignores nil ids safely" do
    expect(store.record("u1", nil, 1)).to be_nil
    expect(store.net("u1", nil)).to eq(0)
  end

  it "exposes the full feedback map for a user" do
    store.record("u1", "a", 2)
    store.record("u1", "b", -1)
    expect(store.all("u1")).to eq("a" => 2, "b" => -1)
  end

  it "persists across instances backed by the same store" do
    backend = Llmemory::ShortTerm::Stores::MemoryStore.new
    described_class.new(store: backend).record("u1", "item_1", 3)
    expect(described_class.new(store: backend).net("u1", "item_1")).to eq(3)
  end
end
