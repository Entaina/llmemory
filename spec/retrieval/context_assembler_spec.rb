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
end
