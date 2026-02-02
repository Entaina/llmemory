# frozen_string_literal: true

RSpec.describe Llmemory::LongTerm::FileBased::Storages::MemoryStorage do
  let(:storage) { described_class.new }
  let(:user_id) { "user_1" }

  it "saves and loads resources" do
    id = storage.save_resource(user_id, "Raw conversation")
    expect(id).to start_with("res_")
    resources = storage.get_all_resources(user_id)
    expect(resources.size).to eq(1)
    expect(resources.first[:text]).to eq("Raw conversation")
  end

  it "saves and loads items" do
    storage.save_resource(user_id, "text")
    id = storage.save_item(user_id, category: "work", content: "User likes Ruby", source_resource_id: "res_1")
    expect(id).to start_with("item_")
    items = storage.get_all_items(user_id)
    expect(items.any? { |i| i[:content] == "User likes Ruby" }).to be true
  end

  it "saves and loads categories" do
    storage.save_category(user_id, "preferences", "# Profile\n- Vegan")
    expect(storage.load_category(user_id, "preferences")).to include("Vegan")
    expect(storage.list_categories(user_id)).to include("preferences")
  end

  it "search_items returns matching items" do
    storage.save_item(user_id, category: "x", content: "User loves Python", source_resource_id: "r1")
    results = storage.search_items(user_id, "Python")
    expect(results.any? { |r| r[:content].include?("Python") }).to be true
  end

  describe "inspection" do
    it "list_users returns unique user ids" do
      storage.save_resource("u1", "t1")
      storage.save_item("u1", category: "c", content: "x", source_resource_id: "r1")
      storage.save_category("u2", "cat", "content")
      expect(storage.list_users.sort).to eq(%w[u1 u2])
    end

    it "list_resources respects limit" do
      storage.save_resource(user_id, "a")
      storage.save_resource(user_id, "b")
      storage.save_resource(user_id, "c")
      expect(storage.list_resources(user_id: user_id).size).to eq(3)
      expect(storage.list_resources(user_id: user_id, limit: 2).size).to eq(2)
    end

    it "list_items filters by category and respects limit" do
      storage.save_item(user_id, category: "work", content: "a", source_resource_id: "r1")
      storage.save_item(user_id, category: "work", content: "b", source_resource_id: "r1")
      storage.save_item(user_id, category: "life", content: "c", source_resource_id: "r1")
      expect(storage.list_items(user_id: user_id).size).to eq(3)
      expect(storage.list_items(user_id: user_id, category: "work").size).to eq(2)
      expect(storage.list_items(user_id: user_id, limit: 2).size).to eq(2)
    end

    it "count_items returns item count" do
      storage.save_item(user_id, category: "x", content: "a", source_resource_id: "r1")
      storage.save_item(user_id, category: "x", content: "b", source_resource_id: "r1")
      expect(storage.count_items(user_id: user_id)).to eq(2)
    end
  end
end
