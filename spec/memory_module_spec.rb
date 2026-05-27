# frozen_string_literal: true

# Parameterized contract: every queryable long-term memory must honor the same
# uniform MemoryModule surface (read / write / list / stats).
RSpec.shared_examples "a memory module" do
  it "is a MemoryModule" do
    expect(memory).to be_a(Llmemory::MemoryModule)
  end

  it "exposes the uniform interface" do
    expect(memory).to respond_to(:read, :write, :list, :stats)
  end

  it "persists via #write and surfaces entries via #list" do
    perform_write
    expect(memory.list).to be_an(Array)
    expect(memory.list).not_to be_empty
  end

  it "retrieves relevant entries via #read" do
    perform_write
    results = memory.read(query)
    expect(results).to be_an(Array)
    expect(results).not_to be_empty
  end

  it "reports counts via #stats" do
    perform_write
    expect(memory.stats).to be_a(Hash)
    expect(memory.stats.values.sum).to be > 0
  end
end

RSpec.describe "MemoryModule contract" do
  let(:user_id) { "user_1" }

  describe Llmemory::LongTerm::Episodic::Memory do
    let(:memory) { described_class.new(user_id: user_id) }
    let(:query) { "rolled back" }
    def perform_write
      memory.write(steps: [{ observation: "deploy failed", action: "rolled back" }], outcome: "recovered")
    end

    include_examples "a memory module"
  end

  describe Llmemory::LongTerm::FileBased::Memory do
    let(:llm) do
      double("LLM").tap do |d|
        allow(d).to receive(:invoke).and_return("[]")
        allow(d).to receive(:invoke).with(/Extract discrete facts/).and_return('[{"content": "User prefers Ruby", "importance": 0.9}]')
        allow(d).to receive(:invoke).with(/Classify this fact/).and_return("preferences")
        allow(d).to receive(:invoke).with(/Memory Synchronization Specialist/).and_return("# Profile\n- User prefers Ruby")
      end
    end
    let(:memory) do
      described_class.new(user_id: user_id, storage: Llmemory::LongTerm::FileBased::Storages::MemoryStorage.new, llm: llm)
    end
    let(:query) { "Ruby" }
    def perform_write
      memory.write("I prefer Ruby")
    end

    include_examples "a memory module"
  end

  describe Llmemory::LongTerm::GraphBased::Memory do
    let(:extractor) do
      double("EntityRelationExtractor").tap do |d|
        allow(d).to receive(:extract).and_return(
          entities: [{ type: "person", name: "User" }, { type: "company", name: "Acme" }],
          relations: [{ subject: "User", predicate: "works_at", object: "Acme" }]
        )
      end
    end
    let(:vector_store) do
      double("VectorStore").tap do |d|
        allow(d).to receive(:embed).and_return([0.1] * 1536)
        allow(d).to receive(:store).and_return("edge_1")
        allow(d).to receive(:search_by_text).and_return(
          [{ id: "e1", score: 0.9, metadata: { "text" => "User works_at Acme", "created_at" => Time.now } }]
        )
      end
    end
    let(:memory) do
      described_class.new(
        user_id: user_id,
        storage: Llmemory::LongTerm::GraphBased::Storages::MemoryStorage.new,
        vector_store: vector_store,
        extractor: extractor
      )
    end
    let(:query) { "work" }
    def perform_write
      memory.write("I work at Acme.")
    end

    include_examples "a memory module"
  end

  describe Llmemory::LongTerm::Procedural::Memory do
    let(:memory) { described_class.new(user_id: user_id) }
    let(:query) { "rollback" }
    def perform_write
      memory.write(name: "rollback", description: "revert a bad deploy", body: "kubectl rollout undo")
    end

    include_examples "a memory module"
  end
end
