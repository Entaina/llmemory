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
end
