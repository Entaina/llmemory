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

  describe "inspection" do
    it "list_users returns unique user ids" do
      expect(store.list_users).to eq([])
      store.save("u1", "s1", {})
      store.save("u1", "s2", {})
      store.save("u2", "s1", {})
      expect(store.list_users.sort).to eq(%w[u1 u2])
    end

    it "list_sessions returns session ids for a user" do
      store.save("u1", "s1", {})
      store.save("u1", "s2", {})
      store.save("u2", "s1", {})
      expect(store.list_sessions(user_id: "u1").sort).to eq(%w[s1 s2])
      expect(store.list_sessions(user_id: "u2")).to eq(%w[s1])
    end
  end
end
