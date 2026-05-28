# frozen_string_literal: true

RSpec.describe Llmemory::ShortTerm::SessionLifecycle do
  let(:store) { Llmemory::ShortTerm::Stores::MemoryStore.new }
  let(:lifecycle) { described_class.new(store: store) }

  describe "#cleanup_idle_sessions!" do
    it "deletes sessions idle longer than threshold" do
      store.save("user1", "s1", { messages: [], last_activity_at: Time.now - 7200 })
      store.save("user1", "s2", { messages: [], last_activity_at: Time.now - 60 })

      deleted = lifecycle.cleanup_idle_sessions!(user_id: "user1", idle_minutes: 60)
      expect(deleted).to eq(1)
      expect(store.load("user1", "s1")).to be_nil
      expect(store.load("user1", "s2")).not_to be_nil
    end

    it "keeps sessions with nil last_activity_at" do
      store.save("user1", "s1", { messages: [] })

      deleted = lifecycle.cleanup_idle_sessions!(user_id: "user1", idle_minutes: 1)
      expect(deleted).to eq(0)
    end
  end

  describe "#cleanup_stale_sessions!" do
    it "deletes sessions older than prune_after_days" do
      store.save("user1", "s1", { messages: [], last_activity_at: Time.now - (35 * 86400) })
      store.save("user1", "s2", { messages: [], last_activity_at: Time.now - (10 * 86400) })

      deleted = lifecycle.cleanup_stale_sessions!(user_id: "user1", prune_after_days: 30)
      expect(deleted).to eq(1)
      expect(store.load("user1", "s1")).to be_nil
    end
  end

  describe "#enforce_max_entries!" do
    it "deletes oldest sessions when over max_entries" do
      5.times do |i|
        store.save("user1", "s#{i}", { messages: [], last_activity_at: Time.now - (i * 3600) })
      end

      deleted = lifecycle.enforce_max_entries!(user_id: "user1", max_entries: 3)
      expect(deleted).to eq(2)
      expect(store.list_sessions(user_id: "user1").size).to eq(3)
    end
  end

  describe "pseudo-session exclusion (SF6 + SF12)" do
    it "skips ForgetLog, FeedbackStore and WorkingMemory pseudo-sessions in lifecycle ops" do
      # Real user session (counts).
      store.save("user1", "s1", { messages: [], last_activity_at: Time.now })
      # Pseudo-sessions sharing the K/V backend.
      store.save("user1", "__forget_log__", { entries: [{ memory_type: "file_based", ids: ["x"] }] })
      store.save("user1", "__retrieval_feedback__", { "item_a" => 3 })
      store.save("user1", "default:working_memory", { goals: ["plan"] })

      deleted = lifecycle.enforce_max_entries!(user_id: "user1", max_entries: 0)

      # Only the real session is countable / deletable; pseudo-sessions remain.
      expect(deleted).to eq(1)
      expect(store.load("user1", "__forget_log__")).not_to be_nil
      expect(store.load("user1", "__retrieval_feedback__")).not_to be_nil
      expect(store.load("user1", "default:working_memory")).not_to be_nil
    end

    it "identifies the documented pseudo-session formats" do
      expect(described_class.pseudo_session?("__forget_log__")).to be true
      expect(described_class.pseudo_session?("__retrieval_feedback__")).to be true
      expect(described_class.pseudo_session?("default:working_memory")).to be true
      expect(described_class.pseudo_session?("regular_session")).to be false
    end
  end
end
