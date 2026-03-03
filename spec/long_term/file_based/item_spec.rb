# frozen_string_literal: true

RSpec.describe Llmemory::LongTerm::FileBased::Item do
  let(:item) do
    described_class.new(
      id: "item_1",
      user_id: "user_1",
      category: "preferences",
      content: "User prefers Ruby",
      source_resource_id: "res_1",
      created_at: Time.utc(2024, 1, 15, 12, 0, 0)
    )
  end

  describe "#initialize" do
    it "sets attributes" do
      expect(item.id).to eq("item_1")
      expect(item.user_id).to eq("user_1")
      expect(item.category).to eq("preferences")
      expect(item.content).to eq("User prefers Ruby")
      expect(item.source_resource_id).to eq("res_1")
      expect(item.created_at).to eq(Time.utc(2024, 1, 15, 12, 0, 0))
    end

    it "defaults created_at to Time.now when nil" do
      before = Time.now
      item_with_default = described_class.new(
        id: "i1",
        user_id: "u1",
        category: "cat",
        content: "content"
      )
      after = Time.now
      expect(item_with_default.created_at).to be_between(before, after)
    end

    it "allows nil source_resource_id" do
      item_nil = described_class.new(
        id: "i1",
        user_id: "u1",
        category: "cat",
        content: "content"
      )
      expect(item_nil.source_resource_id).to be_nil
    end
  end

  describe "#to_h" do
    it "returns hash with iso8601 timestamp" do
      h = item.to_h
      expect(h).to eq(
        id: "item_1",
        user_id: "user_1",
        category: "preferences",
        content: "User prefers Ruby",
        source_resource_id: "res_1",
        created_at: "2024-01-15T12:00:00Z"
      )
    end
  end
end
