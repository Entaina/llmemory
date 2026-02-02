# frozen_string_literal: true

RSpec.describe Llmemory::LongTerm::GraphBased::Storages::MemoryStorage do
  let(:storage) { described_class.new }
  let(:user_id) { "user_1" }

  describe "inspection" do
    it "list_users returns unique user ids" do
      storage.save_node(user_id, Llmemory::LongTerm::GraphBased::Node.new(entity_type: "person", name: "A"))
      storage.save_node("u2", Llmemory::LongTerm::GraphBased::Node.new(entity_type: "person", name: "B"))
      expect(storage.list_users).to contain_exactly(user_id, "u2")
    end

    it "list_nodes accepts entity_type and limit" do
      storage.save_node(user_id, Llmemory::LongTerm::GraphBased::Node.new(entity_type: "person", name: "Alice"))
      storage.save_node(user_id, Llmemory::LongTerm::GraphBased::Node.new(entity_type: "company", name: "Acme"))
      storage.save_node(user_id, Llmemory::LongTerm::GraphBased::Node.new(entity_type: "person", name: "Bob"))
      all = storage.list_nodes(user_id)
      expect(all.size).to eq(3)
      persons = storage.list_nodes(user_id, entity_type: "person")
      expect(persons.map { |n| n.name }).to contain_exactly("Alice", "Bob")
      limited = storage.list_nodes(user_id, limit: 2)
      expect(limited.size).to eq(2)
    end

    it "list_edges returns edges with optional filters" do
      storage.save_node(user_id, Llmemory::LongTerm::GraphBased::Node.new(id: "n1", entity_type: "person", name: "A"))
      storage.save_node(user_id, Llmemory::LongTerm::GraphBased::Node.new(id: "n2", entity_type: "company", name: "B"))
      storage.save_edge(user_id, Llmemory::LongTerm::GraphBased::Edge.new(subject_id: "n1", predicate: "works_at", object_id: "n2"))
      edges = storage.list_edges(user_id)
      expect(edges.size).to eq(1)
      expect(edges.first.predicate).to eq("works_at")
      expect(storage.list_edges(user_id, limit: 0)).to eq([])
    end

    it "count_nodes and count_edges return counts" do
      storage.save_node(user_id, Llmemory::LongTerm::GraphBased::Node.new(entity_type: "person", name: "X"))
      storage.save_node(user_id, Llmemory::LongTerm::GraphBased::Node.new(entity_type: "person", name: "Y"))
      storage.save_edge(user_id, Llmemory::LongTerm::GraphBased::Edge.new(subject_id: "node_1", predicate: "knows", object_id: "node_2"))
      expect(storage.count_nodes(user_id)).to eq(2)
      expect(storage.count_edges(user_id)).to eq(1)
    end
  end
end
