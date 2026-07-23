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

    it "does not collide when ids contain colons" do
      store.save("a:b", "c", { data: 1 })
      store.save("a", "b:c", { data: 2 })
      expect(store.load("a:b", "c")).to eq({ data: 1 })
      expect(store.load("a", "b:c")).to eq({ data: 2 })
      expect(store.list_users.sort).to eq(%w[a a:b])
    end

    it "returns a deep copy so callers cannot mutate persisted state" do
      store.save("u1", "s1", { messages: [{ role: :user, content: "hi" }] })
      msgs = store.load("u1", "s1")[:messages]
      msgs[0][:content] = "mutated"
      expect(store.load("u1", "s1")[:messages].first[:content]).to eq("hi")
    end
  end

  describe "#update" do
    it "serializes concurrent updates without losing messages" do
      store.save("u1", "s1", { messages: [] })
      threads = 2.times.map do |i|
        Thread.new do
          store.update("u1", "s1") do |state|
            state ||= {}
            msgs = (state[:messages] || []).dup
            msgs << { role: :user, content: "msg#{i}" }
            state.merge(messages: msgs)
          end
        end
      end
      threads.each(&:join)
      contents = store.load("u1", "s1")[:messages].map { |m| m[:content] }
      expect(contents).to contain_exactly("msg0", "msg1")
    end
  end
end
