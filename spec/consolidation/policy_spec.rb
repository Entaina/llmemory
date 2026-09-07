# frozen_string_literal: true

require "spec_helper"

RSpec.describe Llmemory::Consolidation::NullPolicy do
  subject(:policy) { described_class.new }

  it "always keeps units" do
    unit = Llmemory::Consolidation::Unit.from_relation(
      subject: "User", predicate: "works_at", object: "Acme"
    )
    expect(policy.decide(unit)).to eq(:keep)
  end
end

RSpec.describe Llmemory::Consolidation::RuleBasedPolicy do
  subject(:policy) do
    described_class.new(
      drop_predicates: %w[works_at current_job],
      volatile_predicates: %w[prefers],
      drop_categories: %w[work_life],
      volatile_categories: %w[general],
      drop_if: drop_if,
      volatile_if: volatile_if
    )
  end

  let(:drop_if) { nil }
  let(:volatile_if) { nil }

  describe "#decide for relations" do
    it "drops matching predicates" do
      unit = Llmemory::Consolidation::Unit.from_relation(
        subject: "User", predicate: "works_at", object: "Acme"
      )
      expect(policy.decide(unit)).to eq(:drop)
    end

    it "marks volatile predicates" do
      unit = Llmemory::Consolidation::Unit.from_relation(
        subject: "User", predicate: "prefers", object: "Ruby"
      )
      expect(policy.decide(unit)).to eq(:volatile)
    end

    it "keeps unrelated predicates" do
      unit = Llmemory::Consolidation::Unit.from_relation(
        subject: "User", predicate: "has_son", object: "Luis"
      )
      expect(policy.decide(unit)).to eq(:keep)
    end

    it "normalizes predicate spacing and case" do
      unit = Llmemory::Consolidation::Unit.from_relation(
        subject: "User", predicate: "Works At", object: "Acme"
      )
      expect(policy.decide(unit)).to eq(:drop)
    end
  end

  describe "#decide for items" do
    it "drops matching categories" do
      unit = Llmemory::Consolidation::Unit.from_item(
        {"content" => "User is a PM"},
        category: "work_life"
      )
      expect(policy.decide(unit)).to eq(:drop)
    end

    it "marks volatile categories" do
      unit = Llmemory::Consolidation::Unit.from_item(
        {"content" => "User mentioned weather"},
        category: "general"
      )
      expect(policy.decide(unit)).to eq(:volatile)
    end
  end

  describe "callable precedence" do
    let(:drop_if) { ->(unit) { unit.content.to_s.include?("secret") } }
    let(:volatile_if) { ->(unit) { unit.predicate == "likes" } }

    it "drop_if wins over volatile_if" do
      unit = Llmemory::Consolidation::Unit.from_item({"content" => "secret plan"})
      expect(policy.decide(unit)).to eq(:drop)
    end

    it "volatile_if wins over predicate lists" do
      unit = Llmemory::Consolidation::Unit.from_relation(
        subject: "User", predicate: "likes", object: "coffee"
      )
      expect(policy.decide(unit)).to eq(:volatile)
    end
  end
end

RSpec.describe Llmemory::Consolidation::Filter do
  let(:policy) do
    Llmemory::Consolidation::RuleBasedPolicy.new(
      drop_predicates: %w[works_at],
      drop_categories: %w[work_life]
    )
  end

  before do
    allow(Llmemory.configuration).to receive(:consolidation_policy).and_return(policy)
  end

  describe ".apply_relations" do
    it "removes dropped relations and marks volatile ones" do
      relation_policy = Llmemory::Consolidation::RuleBasedPolicy.new(
        drop_predicates: %w[works_at],
        volatile_predicates: %w[prefers]
      )
      allow(Llmemory.configuration).to receive(:consolidation_policy).and_return(relation_policy)

      result = described_class.apply_relations([
        {subject: "User", predicate: "works_at", object: "Acme"},
        {subject: "User", predicate: "prefers", object: "Ruby"},
        {subject: "User", predicate: "has_son", object: "Luis"}
      ])

      expect(result.map { |r| r[:predicate] }).to eq(%w[prefers has_son])
      expect(result.find { |r| r[:predicate] == "prefers" }[:volatile]).to be true
      expect(result.find { |r| r[:predicate] == "has_son" }[:volatile]).to be false
    end
  end

  describe ".apply_items" do
    it "removes dropped items" do
      items = [{"content" => "User is a PM", "importance" => 0.8}]
      classifications = {"User is a PM" => "work_life"}

      result = described_class.apply_items(items, classifications)
      expect(result).to be_empty
    end
  end

  describe ".volatile_marked?" do
    it "detects property and provenance flags" do
      expect(described_class.volatile_marked?("consolidation_volatile" => true)).to be true
      expect(described_class.volatile_marked?("consolidation" => "volatile")).to be true
      expect(described_class.volatile_marked?({})).to be false
    end
  end
end
