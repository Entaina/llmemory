# frozen_string_literal: true

RSpec.describe Llmemory::Retrieval::ContextAssembler do
  let(:assembler) { described_class.new(max_tokens: 100) }

  it "assembles context within token budget" do
    ranked = [
      { text: "Memory one", timestamp: Time.now, temporal_score: 0.9 },
      { text: "Memory two", timestamp: Time.now, temporal_score: 0.8 }
    ]
    result = assembler.assemble(ranked)
    expect(result).to include("=== RELEVANT MEMORIES ===")
    expect(result).to include("Memory one")
    expect(result).to include("Memory two")
    expect(result).to include("=== END MEMORIES ===")
  end

  it "stops when max_tokens exceeded" do
    long_text = "x" * 500
    ranked = [
      { text: long_text, timestamp: Time.now, temporal_score: 0.9 },
      { text: "second", timestamp: Time.now, temporal_score: 0.8 }
    ]
    result = assembler.assemble(ranked, max_tokens: 50)
    expect(result).not_to include("second")
  end

  it "labels volatile memories when retrieval_label_volatile is enabled" do
    allow(Llmemory.configuration).to receive(:retrieval_label_volatile).and_return(true)
    ranked = [{ text: "User works at Acme", timestamp: Time.now, score: 0.9, volatile: true }]
    result = assembler.assemble(ranked)
    expect(result).to include("[verify live] User works at Acme")
  end

  it "does not label volatile memories when retrieval_label_volatile is disabled" do
    allow(Llmemory.configuration).to receive(:retrieval_label_volatile).and_return(false)
    ranked = [{ text: "User works at Acme", timestamp: Time.now, score: 0.9, volatile: true }]
    result = assembler.assemble(ranked)
    expect(result).to include("User works at Acme")
    expect(result).not_to include("[verify live]")
  end
end
