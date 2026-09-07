# frozen_string_literal: true

require "spec_helper"

RSpec.describe Llmemory::Maintenance::PolicyPrune do
  let(:user_id) { "user_prune" }
  let(:policy) { Llmemory::Consolidation::RuleBasedPolicy.new(drop_predicates: %w[works_at]) }

  describe "graph-based memory" do
    let(:storage) { Llmemory::LongTerm::GraphBased::Storages::MemoryStorage.new }
    let(:extractor_double) do
      double("EntityRelationExtractor").tap do |d|
        allow(d).to receive(:extract).and_return(
          entities: [{ type: "person", name: "User" }, { type: "company", name: "Acme" }],
          relations: [{ subject: "User", predicate: "works_at", object: "Acme" }]
        )
      end
    end
    let(:vector_store_double) do
      double("VectorStore").tap do |d|
        allow(d).to receive(:embed).and_return([0.1] * 1536)
        allow(d).to receive(:store).and_return("edge_1")
        allow(d).to receive(:delete).and_return(true)
      end
    end
    let(:memory) do
      Llmemory::LongTerm::GraphBased::Memory.new(
        user_id: user_id,
        storage: storage,
        vector_store: vector_store_double,
        extractor: extractor_double
      )
    end

    before { memory.memorize("I work at Acme.") }

    it "archives edges that the policy would drop" do
      edge = storage.find_edges(user_id, predicate: "works_at", include_archived: false).first
      expect(edge).not_to be_nil

      result = described_class.new(policy: policy).run(memory: memory)

      expect(result.graph_edges).to eq(1)
      expect(storage.find_edges(user_id, predicate: "works_at", include_archived: false)).to be_empty
    end

    it "does not archive in dry run mode" do
      result = described_class.new(policy: policy, dry_run: true).run(memory: memory)
      expect(result.graph_edges).to eq(1)
      expect(storage.find_edges(user_id, predicate: "works_at", include_archived: false).size).to eq(1)
    end
  end

  describe "file-based memory" do
    let(:storage) { Llmemory::LongTerm::FileBased::Storage.new }
    let(:llm_double) do
      double("LLM").tap do |d|
        allow(d).to receive(:invoke).with(/Extract discrete facts/).and_return('[{"content": "User is a PM"}]')
        allow(d).to receive(:invoke).with(/Classify this fact/).and_return("work_life")
        allow(d).to receive(:invoke).with(/Memory Synchronization Specialist/).and_return("# Profile\n- PM")
      end
    end
    let(:memory) { Llmemory::LongTerm::FileBased::Memory.new(user_id: user_id, storage: storage, llm: llm_double) }
    let(:file_policy) { Llmemory::Consolidation::RuleBasedPolicy.new(drop_categories: %w[work_life]) }

    before { memory.memorize("conversation") }

    it "removes items that the policy would drop" do
      expect(storage.get_all_items(user_id).size).to eq(1)

      result = described_class.new(policy: file_policy).run(memory: memory)

      expect(result.file_items).to eq(1)
      expect(storage.get_all_items(user_id)).to be_empty
    end
  end
end
