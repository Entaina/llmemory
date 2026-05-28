# frozen_string_literal: true

RSpec.describe Llmemory::VectorStore do
  describe ".build" do
    it "returns an in-process MemoryStore by default" do
      expect(described_class.build).to be_a(Llmemory::VectorStore::MemoryStore)
    end

    it "wires an embedding provider into the store" do
      store = described_class.build(source_type: "episode")
      expect(store).to respond_to(:embed, :store, :search_by_text)
    end

    it "uses ActiveRecordStore with the given source_type when configured", skip: (defined?(ActiveRecord) ? false : "ActiveRecord not in bundle") do
      allow(Llmemory.configuration).to receive(:long_term_store).and_return(:active_record)
      expect(described_class.build(source_type: "episode")).to be_a(Llmemory::VectorStore::ActiveRecordStore)
    end
  end
end
