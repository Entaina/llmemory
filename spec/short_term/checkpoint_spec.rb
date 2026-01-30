# frozen_string_literal: true

RSpec.describe Llmemory::ShortTerm::Checkpoint do
  let(:user_id) { "user_123" }
  let(:store) { Llmemory::ShortTerm::Stores::MemoryStore.new }
  let(:checkpoint) { described_class.new(user_id: user_id, store: store) }

  describe "#save_state and #restore_state" do
    it "saves and restores conversation state" do
      state = { messages: [{ role: "user", content: "Hello" }] }
      checkpoint.save_state(state)
      expect(checkpoint.restore_state).to eq(state)
    end

    it "returns nil when no state exists" do
      expect(checkpoint.restore_state).to be_nil
    end
    it "overwrites previous state" do
      checkpoint.save_state({ a: 1 })
      checkpoint.save_state({ b: 2 })
      expect(checkpoint.restore_state).to eq({ b: 2 })
    end
  end

  describe "#clear_state" do
    it "removes saved state" do
      checkpoint.save_state({ x: 1 })
      checkpoint.clear_state
      expect(checkpoint.restore_state).to be_nil
    end
  end

  describe "with ActiveRecordStore", skip: (defined?(ActiveRecord) ? false : "ActiveRecord not in bundle") do
    it "builds ActiveRecordStore when short_term_store is :active_record" do
      Llmemory.configure { |c| c.short_term_store = :active_record }
      cp = described_class.new(user_id: user_id)
      expect(cp.send(:build_store)).to be_a(Llmemory::ShortTerm::Stores::ActiveRecordStore)
    ensure
      Llmemory.reset_configuration!
    end
  end
end
