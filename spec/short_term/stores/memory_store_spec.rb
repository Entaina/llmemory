# frozen_string_literal: true

RSpec.describe Llmemory::ShortTerm::Stores::MemoryStore do
  let(:store) { described_class.new }

  it "saves and loads state" do
    store.save("u1", "s1", { data: "test" })
    expect(store.load("u1", "s1")).to eq({ data: "test" })
  end

  it "returns nil for missing key" do
    expect(store.load("u1", "s1")).to be_nil
  end

  it "deletes state" do
    store.save("u1", "s1", { x: 1 })
    store.delete("u1", "s1")
    expect(store.load("u1", "s1")).to be_nil
  end
end
