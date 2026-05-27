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
end
