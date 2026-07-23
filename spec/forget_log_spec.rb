# frozen_string_literal: true

RSpec.describe Llmemory::ForgetLog do
  let(:backend) { Llmemory::ShortTerm::Stores::MemoryStore.new }
  let(:log) { described_class.new(store: backend) }

  it "records an entry with type, ids, count, reason and timestamp" do
    entry = log.record("u1", memory_type: "episodic", ids: %w[ep_1 ep_2], reason: "obsolete")
    expect(entry[:memory_type]).to eq("episodic")
    expect(entry[:ids]).to eq(%w[ep_1 ep_2])
    expect(entry[:count]).to eq(2)
    expect(entry[:reason]).to eq("obsolete")
    expect { Time.iso8601(entry[:at]) }.not_to raise_error
  end

  it "accumulates entries per user" do
    log.record("u1", memory_type: "episodic", ids: ["ep_1"])
    log.record("u1", memory_type: "procedural", ids: ["skill_1"])
    expect(log.entries("u1").map { |e| e[:memory_type] }).to eq(%w[episodic procedural])
  end

  it "isolates entries per user" do
    log.record("u1", memory_type: "file_based", ids: ["item_1"])
    expect(log.entries("u2")).to eq([])
  end

  it "persists across instances backed by the same store" do
    log.record("u1", memory_type: "file_based", ids: ["item_1"], reason: "gdpr")
    reloaded = described_class.new(store: backend).entries("u1")
    expect(reloaded.first[:reason]).to eq("gdpr")
  end

  it "uses the orchestrator short-term store when provided via forget_log_store" do
    store = Llmemory::ShortTerm::Stores::MemoryStore.new
    memory = Llmemory::Memory.new(user_id: "u1", checkpoint: Llmemory::ShortTerm::Checkpoint.new(
      user_id: "u1", session_id: "s1", store: store
    ))
    memory.episodic.record_episode(steps: [{ action: "x" }])
    episode_id = memory.episodic.recent_episodes(limit: 1).first.id
    memory.episodic.forget(ids: [episode_id], reason: "test")

    global_log = Llmemory::ForgetLog.new
    expect(global_log.entries("u1")).to be_empty
    expect(log_entries = Llmemory::ForgetLog.new(store: store).entries("u1")).not_to be_empty
    expect(log_entries.last[:memory_type]).to eq("episodic")
  end
end
