# frozen_string_literal: true

require "spec_helper"
require "llmemory/mcp"

RSpec.describe Llmemory::MCP::Tools::MemoryRetrieve do
  before do
    Llmemory.reset_configuration!
    Llmemory.configuration.short_term_store = :memory
    Llmemory.configuration.long_term_store = :memory
    Llmemory.configuration.long_term_type = :file_based
  end

  describe ".call" do
    it "returns a response even when memory is empty" do
      response = described_class.call(query: "test", user_id: "user123")

      expect(response).to be_a(::MCP::Tool::Response)
      # Empty memory still returns formatted output
      expect(response.content.first[:text]).to be_a(String)
    end

    it "retrieves context from memory with short-term messages" do
      # Use shared checkpoint store
      store = Llmemory::ShortTerm::Stores::MemoryStore.new
      allow(Llmemory::ShortTerm::Stores::MemoryStore).to receive(:new).and_return(store)

      # Setup: add a message to short-term
      memory = Llmemory::Memory.new(user_id: "user123", session_id: "default")
      memory.add_message(role: :user, content: "Hello world")

      response = described_class.call(query: "greeting", user_id: "user123")

      expect(response).to be_a(::MCP::Tool::Response)
      expect(response.content.first[:text]).to include("Hello world")
    end

    it "accepts custom session_id" do
      store = Llmemory::ShortTerm::Stores::MemoryStore.new
      allow(Llmemory::ShortTerm::Stores::MemoryStore).to receive(:new).and_return(store)

      memory = Llmemory::Memory.new(user_id: "user123", session_id: "custom_session")
      memory.add_message(role: :user, content: "Custom session message")

      response = described_class.call(query: "message", user_id: "user123", session_id: "custom_session")

      expect(response.content.first[:text]).to include("Custom session message")
    end

    it "handles errors gracefully" do
      allow(Llmemory::Memory).to receive(:new).and_raise(StandardError.new("Test error"))

      response = described_class.call(query: "test", user_id: "user123")

      expect(response.instance_variable_get(:@error)).to be true
      expect(response.content.first[:text]).to include("Error")
    end

    context "with timeline context" do
      it "includes timeline context when include_timeline_context is true" do
        storage = Llmemory::LongTerm::FileBased::Storages::MemoryStorage.new
        allow(Llmemory::LongTerm::FileBased::Storages).to receive(:build).and_return(storage)

        short_term_store = Llmemory::ShortTerm::Stores::MemoryStore.new
        allow(Llmemory::ShortTerm::Stores::MemoryStore).to receive(:new).and_return(short_term_store)

        # Create several items
        5.times do |i|
          storage.save_item(
            "user123",
            category: "observations",
            content: "Memory item #{i + 1}",
            source_resource_id: nil
          )
          sleep 0.01
        end

        # Add a short-term message so retrieve returns something
        memory = Llmemory::Memory.new(user_id: "user123", session_id: "default")
        memory.add_message(role: :user, content: "Tell me about Memory item 3")

        response = described_class.call(
          query: "Memory item 3",
          user_id: "user123",
          include_timeline_context: true,
          timeline_window: 2
        )

        text = response.content.first[:text]
        expect(text).to include("TIMELINE CONTEXT")
        expect(text).to include("BEFORE")
        expect(text).to include("MATCH")
        expect(text).to include("AFTER")
      end

      it "does not include timeline context by default" do
        short_term_store = Llmemory::ShortTerm::Stores::MemoryStore.new
        allow(Llmemory::ShortTerm::Stores::MemoryStore).to receive(:new).and_return(short_term_store)

        memory = Llmemory::Memory.new(user_id: "user123", session_id: "default")
        memory.add_message(role: :user, content: "Hello world")

        response = described_class.call(query: "Hello", user_id: "user123")

        expect(response.content.first[:text]).not_to include("TIMELINE CONTEXT")
      end

      it "works with custom timeline_window" do
        storage = Llmemory::LongTerm::FileBased::Storages::MemoryStorage.new
        allow(Llmemory::LongTerm::FileBased::Storages).to receive(:build).and_return(storage)

        short_term_store = Llmemory::ShortTerm::Stores::MemoryStore.new
        allow(Llmemory::ShortTerm::Stores::MemoryStore).to receive(:new).and_return(short_term_store)

        10.times do |i|
          storage.save_item(
            "user123",
            category: "observations",
            content: "Item number #{i + 1}",
            source_resource_id: nil
          )
          sleep 0.01
        end

        memory = Llmemory::Memory.new(user_id: "user123", session_id: "default")
        memory.add_message(role: :user, content: "Item number 5")

        response = described_class.call(
          query: "Item number 5",
          user_id: "user123",
          include_timeline_context: true,
          timeline_window: 4
        )

        text = response.content.first[:text]
        expect(text).to include("TIMELINE CONTEXT")
      end
    end
  end

  describe "tool definition" do
    it "has a description" do
      expect(described_class.description_value).to include("Retrieve")
    end

    it "requires query and user_id" do
      schema = described_class.input_schema_value.to_h
      expect(schema[:required]).to include("query")
      expect(schema[:required]).to include("user_id")
    end

    it "has optional session_id, max_tokens, include_timeline_context, and timeline_window" do
      schema = described_class.input_schema_value.to_h
      expect(schema[:properties]).to have_key(:session_id)
      expect(schema[:properties]).to have_key(:max_tokens)
      expect(schema[:properties]).to have_key(:include_timeline_context)
      expect(schema[:properties]).to have_key(:timeline_window)
    end
  end
end
