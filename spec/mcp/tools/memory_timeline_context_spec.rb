# frozen_string_literal: true

require "spec_helper"
require "llmemory/mcp"

RSpec.describe Llmemory::MCP::Tools::MemoryTimelineContext do
  before do
    Llmemory.reset_configuration!
    Llmemory.configuration.short_term_store = :memory
    Llmemory.configuration.long_term_store = :memory
    Llmemory.configuration.long_term_type = :file_based
  end

  describe ".call" do
    it "returns error when neither item_id nor timestamp provided" do
      response = described_class.call(user_id: "user123")

      expect(response).to be_a(::MCP::Tool::Response)
      expect(response.instance_variable_get(:@error)).to be true
      expect(response.content.first[:text]).to include("Either item_id or timestamp must be provided")
    end

    it "returns no memories when store is empty" do
      response = described_class.call(user_id: "user123", item_id: "nonexistent")

      expect(response).to be_a(::MCP::Tool::Response)
      expect(response.content.first[:text]).to include("No memories found")
    end

    it "returns context around an item by id" do
      storage = Llmemory::LongTerm::FileBased::Storages::MemoryStorage.new
      allow(Llmemory::LongTerm::FileBased::Storages).to receive(:build).and_return(storage)

      # Create several items with different timestamps
      item_ids = []
      5.times do |i|
        id = storage.save_item(
          "user123",
          category: "observations",
          content: "Memory item #{i + 1}",
          source_resource_id: nil
        )
        item_ids << id
        sleep 0.01 # Ensure different timestamps
      end

      # Get context around the middle item
      response = described_class.call(user_id: "user123", item_id: item_ids[2], before: 2, after: 2)

      expect(response).to be_a(::MCP::Tool::Response)
      text = response.content.first[:text]
      expect(text).to include("Timeline Context")
      expect(text).to include("BEFORE")
      expect(text).to include("TARGET")
      expect(text).to include("AFTER")
      expect(text).to include("Memory item 3")
    end

    it "returns context around a timestamp" do
      storage = Llmemory::LongTerm::FileBased::Storages::MemoryStorage.new
      allow(Llmemory::LongTerm::FileBased::Storages).to receive(:build).and_return(storage)

      # Create several items
      3.times do |i|
        storage.save_item(
          "user123",
          category: "observations",
          content: "Memory item #{i + 1}",
          source_resource_id: nil
        )
        sleep 0.01
      end

      # Use current time as reference (should find items before it)
      timestamp = Time.now.iso8601
      response = described_class.call(user_id: "user123", timestamp: timestamp, before: 3, after: 0)

      expect(response).to be_a(::MCP::Tool::Response)
      text = response.content.first[:text]
      expect(text).to include("Timeline Context")
    end

    it "returns context around graph edges when graph_based" do
      Llmemory.configuration.long_term_type = :graph_based
      storage = Llmemory::LongTerm::GraphBased::Storages::MemoryStorage.new
      allow(Llmemory::LongTerm::GraphBased::Storages).to receive(:build).and_return(storage)

      edge_ids = 3.times.map do |i|
        id = storage.save_edge(
          "user123",
          Llmemory::LongTerm::GraphBased::Edge.new(
            subject_id: "n#{i}",
            predicate: "relates_to",
            target_id: "n#{i + 1}"
          )
        )
        sleep 0.01
        id
      end

      response = described_class.call(user_id: "user123", item_id: edge_ids[1], before: 1, after: 1)

      text = response.content.first[:text]
      expect(text).to include("Timeline Context")
      expect(text).to include("relates_to")
    end

    it "handles errors gracefully" do
      allow(Llmemory::LongTerm::FileBased::Storages).to receive(:build).and_raise(StandardError.new("Storage error"))

      response = described_class.call(user_id: "user123", item_id: "test")

      expect(response.instance_variable_get(:@error)).to be true
      expect(response.content.first[:text]).to include("Error")
    end
  end

  describe "tool definition" do
    it "has a description" do
      expect(described_class.description_value).to include("temporal context")
    end

    it "requires only user_id" do
      schema = described_class.input_schema_value.to_h
      expect(schema[:required]).to eq(["user_id"])
    end

    it "has optional item_id, timestamp, before, and after" do
      schema = described_class.input_schema_value.to_h
      expect(schema[:properties]).to have_key(:item_id)
      expect(schema[:properties]).to have_key(:timestamp)
      expect(schema[:properties]).to have_key(:before)
      expect(schema[:properties]).to have_key(:after)
    end
  end
end
