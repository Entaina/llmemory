# frozen_string_literal: true

require "tmpdir"

RSpec.describe Llmemory::LongTerm::FileBased::Storages::FileStorage do
  let(:tmpdir) { Dir.mktmpdir("llmemory_file_storage") }
  let(:storage) { described_class.new(base_path: tmpdir) }
  let(:user_id) { "user_1" }

  after { FileUtils.rm_rf(tmpdir) }

  it "persists resources to files" do
    id = storage.save_resource(user_id, "Raw text")
    expect(id).to start_with("res_")
    expect(File).to exist(File.join(tmpdir, "user_1", "resources", "#{id}.json"))
    resources = storage.get_all_resources(user_id)
    expect(resources.first[:text]).to eq("Raw text")
  end

  it "persists and loads categories as markdown files" do
    storage.save_category(user_id, "preferences", "# Profile\n- Vegan")
    path = File.join(tmpdir, "user_1", "categories", "preferences.md")
    expect(File).to exist(path)
    expect(File.read(path)).to include("Vegan")
    expect(storage.load_category(user_id, "preferences")).to include("Vegan")
    expect(storage.list_categories(user_id)).to include("preferences")
  end

  it "persists items and search works" do
    storage.save_item(user_id, category: "work", content: "User prefers Ruby", source_resource_id: "r1")
    items = storage.get_all_items(user_id)
    expect(items.any? { |i| i[:content] == "User prefers Ruby" }).to be true
    results = storage.search_items(user_id, "Ruby")
    expect(results.any? { |r| r[:content].include?("Ruby") }).to be true
  end

  it "survives new instance (persistence)" do
    storage.save_category(user_id, "test_cat", "content here")
    storage2 = described_class.new(base_path: tmpdir)
    expect(storage2.load_category(user_id, "test_cat")).to eq("content here")
  end

  describe "#get_items_around" do
    it "returns surrounding items by id" do
      ids = 5.times.map do |i|
        id = storage.save_item(user_id, category: "obs", content: "Item #{i + 1}", source_resource_id: nil)
        sleep 0.01
        id
      end

      result = storage.get_items_around(user_id, ids[2], before: 2, after: 1)
      expect(result[:target][:content]).to eq("Item 3")
      expect(result[:before].map { |i| i[:content] }).to eq(["Item 1", "Item 2"])
      expect(result[:after].map { |i| i[:content] }).to eq(["Item 4"])
    end
  end

  describe "#get_resources_around" do
    it "returns surrounding resources by id" do
      ids = 3.times.map do |i|
        id = storage.save_resource(user_id, "Resource #{i + 1}")
        sleep 0.01
        id
      end

      result = storage.get_resources_around(user_id, ids[1], before: 1, after: 1)
      expect(result[:target][:text]).to eq("Resource 2")
      expect(result[:before].size).to eq(1)
      expect(result[:after].size).to eq(1)
    end
  end
end
