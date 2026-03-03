# frozen_string_literal: true

RSpec.describe Llmemory::Maintenance::Summarizer do
  let(:storage) { Llmemory::LongTerm::FileBased::Storage.new }
  let(:user_id) { "u1" }
  let(:llm_double) { double("LLM", invoke: "Summary of old memories.") }
  let(:summarizer) { described_class.new(storage, llm: llm_double) }

  before do
    storage.save_item(user_id, category: "work", content: "User works at X", source_resource_id: "r1")
    storage.save_category(user_id, "work", "")
  end

  it "run_weekly returns true" do
    expect(summarizer.run_weekly(user_id)).to be true
  end

  it "archives old items and updates category with summary" do
    old_time = Time.now - (35 * 86400)
    storage_stub = double("Storage").tap do |s|
      allow(s).to receive(:get_items_older_than).with(user_id, days: 30).and_return([
        { id: "i1", category: "work", content: "User worked at Acme", created_at: old_time }
      ])
      allow(s).to receive(:load_category).with(user_id, "work").and_return("")
      allow(s).to receive(:save_category).with(user_id, "work", anything)
      allow(s).to receive(:archive_items).with(user_id, ["i1"])
      allow(s).to receive(:get_items_older_than).with(user_id, days: 90).and_return([])
    end

    summarizer_stub = described_class.new(storage_stub, llm: llm_double)
    expect(summarizer_stub.run_weekly(user_id)).to be true
    expect(storage_stub).to have_received(:save_category).with(user_id, "work", "- User worked at Acme")
    expect(storage_stub).to have_received(:archive_items).with(user_id, ["i1"])
  end

  it "uses custom prune_after_days when provided" do
    storage_stub = double("Storage").tap do |s|
      allow(s).to receive(:get_items_older_than).with(user_id, days: 30).and_return([])
      allow(s).to receive(:get_items_older_than).with(user_id, days: 60).and_return([])
    end

    summarizer_stub = described_class.new(storage_stub, llm: llm_double)
    summarizer_stub.run_weekly(user_id, prune_after_days: 60)
    expect(storage_stub).to have_received(:get_items_older_than).with(user_id, days: 60)
  end
end
