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

  it "paginates #list via limit + offset (non-overlapping windows)" do
    5.times { |i| perform_distinct_write(i) }
    expect(memory.list.size).to be >= 4

    first_page = memory.list(limit: 2, offset: 0)
    second_page = memory.list(limit: 2, offset: 2)

    expect(first_page.size).to eq(2)
    expect(second_page.size).to eq(2)

    first_ids = first_page.map { |e| extract_id(e) }
    second_ids = second_page.map { |e| extract_id(e) }
    expect(first_ids & second_ids).to be_empty
  end
end

def extract_id(entry)
  case entry
  when Hash then (entry[:id] || entry["id"]).to_s
  else entry.respond_to?(:id) ? entry.id.to_s : entry.to_s
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
    def perform_distinct_write(i)
      memory.write(steps: [{ observation: "deploy #{i} failed", action: "rolled back" }], outcome: "recovered #{i}")
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
    def perform_distinct_write(i)
      # Each write creates a fresh resource + item via the LLM mock (idempotent enough for paging).
      memory.write("fact #{i}: I prefer language number #{i}")
    end

    include_examples "a memory module"
  end

  describe Llmemory::LongTerm::GraphBased::Memory do
    let(:extractor) do
      double("EntityRelationExtractor").tap do |d|
        allow(d).to receive(:extract) do |text|
          n = text.to_s[/\d+/]&.to_i || 0
          {
            entities: [{ type: "person", name: "User#{n}" }, { type: "company", name: "Acme#{n}" }],
            relations: [{ subject: "User#{n}", predicate: "works_at", object: "Acme#{n}" }]
          }
        end
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
    def perform_distinct_write(i)
      memory.write("Person #{i} works at company #{i}")
    end

    include_examples "a memory module"
  end

  describe Llmemory::LongTerm::Procedural::Memory do
    let(:memory) { described_class.new(user_id: user_id) }
    let(:query) { "rollback" }
    def perform_write
      memory.write(name: "rollback", description: "revert a bad deploy", body: "kubectl rollout undo")
    end
    def perform_distinct_write(i)
      memory.write(name: "skill_#{i}", description: "task #{i}", body: "run command #{i}")
    end

    include_examples "a memory module"
  end
end
