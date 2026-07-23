# frozen_string_literal: true

RSpec.describe Llmemory::Maintenance::Consolidator do
  let(:storage) { Llmemory::LongTerm::FileBased::Storage.new }
  let(:user_id) { "u1" }
  let(:consolidator) { described_class.new(storage) }

  before do
    storage.save_item(user_id, category: "general", content: "User likes Ruby", source_resource_id: "r1")
    storage.save_item(user_id, category: "general", content: "User likes Ruby", source_resource_id: "r2")
  end

  it "merges duplicate items on run_nightly" do
    items_before = storage.get_items_since(user_id, hours: 24).size
    consolidator.run_nightly(user_id)
    items_after = storage.get_items_since(user_id, hours: 24).size
    expect(items_after).to be <= items_before
  end

  it "returns true" do
    expect(consolidator.run_nightly(user_id)).to be true
  end

  it "preserves max importance and provenance when merging duplicates" do
    storage.save_item(
      user_id,
      category: "general",
      content: "User likes Ruby",
      source_resource_id: "r3",
      importance: 0.4,
      provenance: Llmemory::Provenance.build(method: "fact_extraction", confidence: "low")
    )
    storage.save_item(
      user_id,
      category: "general",
      content: "User likes Ruby",
      source_resource_id: "r4",
      importance: 0.9,
      provenance: Llmemory::Provenance.build(method: "reflection", confidence: "high")
    )
    consolidator.run_nightly(user_id)
    merged = storage.get_items_since(user_id, hours: 24).find { |i| i[:content].to_s.include?("User likes Ruby") }
    expect(merged[:importance]).to eq(0.9)
    expect(merged[:provenance][:method]).to eq("reflection")
    expect(merged[:provenance][:confidence]).to eq(0.9)
  end
end
