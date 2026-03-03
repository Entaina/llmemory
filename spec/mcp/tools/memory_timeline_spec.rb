# frozen_string_literal: true

require "spec_helper"
require "llmemory/mcp"

RSpec.describe Llmemory::MCP::Tools::MemoryTimeline do
  before do
    Llmemory.reset_configuration!
    Llmemory.configuration.short_term_store = :memory
    Llmemory.configuration.long_term_store = :memory
    Llmemory.configuration.long_term_type = :file_based
  end

  describe ".call" do
    it "returns empty timeline when no activity" do
      response = described_class.call(user_id: "user123", hours: 24)

      expect(response).to be_a(::MCP::Tool::Response)
      expect(response.content.first[:text]).to include("No activity in the last 24 hours")
    end

    it "includes facts from long-term memory" do
      storage = Llmemory::LongTerm::FileBased::Storages::MemoryStorage.new
      allow(Llmemory::LongTerm::FileBased::Storages).to receive(:build).and_return(storage)

      storage.save_item(
        "user123",
        category: "preferences",
        content: "User prefers Python",
        source_resource_id: "r1"
      )

      response = described_class.call(user_id: "user123", hours: 24)

      expect(response.content.first[:text]).to include("User prefers Python")
      expect(response.content.first[:text]).to include("[FACT]")
      expect(response.content.first[:text]).to include("[preferences]")
    end

    it "includes messages from short-term when include_messages is true" do
      store = Llmemory::ShortTerm::Stores::MemoryStore.new
      allow(Llmemory::ShortTerm::Stores::MemoryStore).to receive(:new).and_return(store)

      memory = Llmemory::Memory.new(user_id: "user123", session_id: "default")
      memory.add_message(role: :user, content: "Hello from timeline")

      response = described_class.call(user_id: "user123", hours: 24, include_messages: true)

      expect(response.content.first[:text]).to include("Hello from timeline")
      expect(response.content.first[:text]).to include("[MSG")
    end

    it "excludes messages when include_messages is false" do
      store = Llmemory::ShortTerm::Stores::MemoryStore.new
      allow(Llmemory::ShortTerm::Stores::MemoryStore).to receive(:new).and_return(store)

      memory = Llmemory::Memory.new(user_id: "user123", session_id: "default")
      memory.add_message(role: :user, content: "Should not appear")

      response = described_class.call(user_id: "user123", hours: 24, include_messages: false)

      expect(response.content.first[:text]).not_to include("Should not appear")
    end

    it "uses custom hours parameter" do
      response = described_class.call(user_id: "user123", hours: 48)

      expect(response.content.first[:text]).to include("last 48 hours")
    end

    it "handles errors gracefully" do
      storage = double("Storage")
      allow(storage).to receive(:get_items_since).and_raise(StandardError.new("DB error"))
      allow(Llmemory::LongTerm::FileBased::Storages).to receive(:build).and_return(storage)

      response = described_class.call(user_id: "user123", hours: 24)

      expect(response.instance_variable_get(:@error)).to be true
      expect(response.content.first[:text]).to include("Error")
    end
  end

  describe "tool definition" do
    it "has a description" do
      expect(described_class.description_value).to include("timeline")
    end

    it "requires user_id" do
      schema = described_class.input_schema_value.to_h
      expect(schema[:required]).to include("user_id")
    end

    it "has optional hours and include_messages" do
      schema = described_class.input_schema_value.to_h
      expect(schema[:properties]).to have_key(:hours)
      expect(schema[:properties]).to have_key(:include_messages)
    end
  end
end
