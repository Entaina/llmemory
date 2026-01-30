# frozen_string_literal: true

RSpec.describe Llmemory::Retrieval::Engine do
  let(:memory_double) do
    double("Memory", user_id: "user_1").tap do |m|
      allow(m).to receive(:search_candidates).with("hello", user_id: "user_1", top_k: 20).and_return([
        { text: "User said hello before", timestamp: Time.now, score: 1.0 }
      ])
    end
  end
  let(:engine) { described_class.new(memory_double) }

  it "retrieves context for inference" do
    context = engine.retrieve_for_inference("hello", max_tokens: 500)
    expect(context).to include("=== RELEVANT MEMORIES ===")
    expect(context).to include("User said hello before")
  end

  it "uses memory user_id when user_id not passed" do
    expect(memory_double).to receive(:search_candidates).with(anything, hash_including(user_id: "user_1"))
    engine.retrieve_for_inference("hello")
  end
end
