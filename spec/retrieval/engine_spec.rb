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

  describe "adaptive retrieval feedback (P8)" do
    let(:feedback) { Llmemory::Retrieval::FeedbackStore.new(store: Llmemory::ShortTerm::Stores::MemoryStore.new) }
    let(:two_candidates) do
      t = Time.now
      [
        { id: "a", text: "alpha about ruby", timestamp: t, score: 1.0, importance: 0.5 },
        { id: "b", text: "beta about ruby", timestamp: t, score: 1.0, importance: 0.5 }
      ]
    end
    let(:memory) do
      double("Memory", user_id: "user_1").tap do |m|
        allow(m).to receive(:search_candidates).and_return(two_candidates)
      end
    end
    let(:engine) { described_class.new(memory, feedback: feedback) }

    before do
      # Isolate the feedback signal from hybrid/MMR re-scoring.
      allow(Llmemory.configuration).to receive(:hybrid_search_enabled).and_return(false)
      allow(Llmemory.configuration).to receive(:mmr_enabled).and_return(false)
    end

    def order_in(context)
      [["alpha", context.index("alpha")], ["beta", context.index("beta")]]
        .reject { |_, i| i.nil? }.sort_by { |_, i| i }.map(&:first)
    end

    it "ranks repeatedly-useful items above equally-relevant ones" do
      expect(order_in(engine.retrieve_for_inference("ruby"))).to eq(%w[alpha beta])
      engine.report_feedback(useful_ids: %w[b b b])
      expect(order_in(engine.retrieve_for_inference("ruby"))).to eq(%w[beta alpha])
    end

    it "dampens items marked harmful" do
      engine.report_feedback(harmful_ids: %w[a a])
      expect(order_in(engine.retrieve_for_inference("ruby"))).to eq(%w[beta alpha])
    end

    it "does nothing when feedback weight is 0" do
      allow(Llmemory.configuration).to receive(:retrieval_feedback_weight).and_return(0)
      engine.report_feedback(useful_ids: %w[b b b])
      expect(order_in(engine.retrieve_for_inference("ruby"))).to eq(%w[alpha beta])
    end

    it "leaves candidates without an id unaffected and error-free" do
      allow(memory).to receive(:search_candidates).and_return([
        { text: "no id here about ruby", timestamp: Time.now, score: 1.0, importance: 0.5 }
      ])
      engine.report_feedback(useful_ids: ["whatever"])
      expect { engine.retrieve_for_inference("ruby") }.not_to raise_error
    end
  end

  describe "iterative retrieval (P11)" do
    let(:feedback) { Llmemory::Retrieval::FeedbackStore.new(store: Llmemory::ShortTerm::Stores::MemoryStore.new) }
    let(:searched) { [] }
    let(:per_query) do
      t = Time.now
      {
        "capital of France" => [{ id: "c1", text: "France capital is Paris", timestamp: t, score: 1.0 }],
        "population of Paris" => [{ id: "p1", text: "Paris population is 2.1M", timestamp: t, score: 1.0 }],
        "again" => [{ id: "c1", text: "France capital is Paris", timestamp: t, score: 1.0 }]
      }
    end
    let(:llm) { double("LLM") }
    let(:memory) do
      tracker = searched
      data = per_query
      double("Memory", user_id: "user_1").tap do |m|
        allow(m).to receive(:search_candidates) do |query, **|
          tracker << query
          data.fetch(query, [])
        end
      end
    end
    let(:engine) { described_class.new(memory, llm: llm, feedback: feedback) }

    before do
      allow(Llmemory.configuration).to receive(:hybrid_search_enabled).and_return(false)
      allow(Llmemory.configuration).to receive(:mmr_enabled).and_return(false)
    end

    it "performs multiple hops, accumulating context from follow-up queries" do
      hops = ["population of Paris", "DONE"]
      reasoner = ->(_q, _acc, _hop) { hops.shift }
      ctx = engine.iterative_retrieve("capital of France", reasoner: reasoner, max_hops: 3, max_tokens: 500)
      expect(ctx).to include("France capital is Paris")
      expect(ctx).to include("Paris population is 2.1M")
      expect(searched).to eq(["capital of France", "population of Paris"])
    end

    it "stops at max_hops even if the reasoner keeps proposing new queries" do
      reasoner = ->(_q, _acc, _hop) { "population of Paris" }
      engine.iterative_retrieve("capital of France", reasoner: reasoner, max_hops: 2)
      expect(searched).to eq(["capital of France", "population of Paris"])
    end

    it "stops when the reasoner returns DONE" do
      reasoner = ->(*) { "DONE" }
      engine.iterative_retrieve("capital of France", reasoner: reasoner, max_hops: 5)
      expect(searched).to eq(["capital of France"])
    end

    it "stops when the reasoner repeats an already-searched query" do
      reasoner = ->(*) { "capital of France" }
      engine.iterative_retrieve("capital of France", reasoner: reasoner, max_hops: 5)
      expect(searched).to eq(["capital of France"])
    end

    it "uses the LLM to propose follow-up queries by default" do
      allow(llm).to receive(:invoke).and_return("population of Paris", "DONE")
      ctx = engine.iterative_retrieve("capital of France", max_hops: 3, max_tokens: 500)
      expect(ctx).to include("Paris population is 2.1M")
    end

    it "deduplicates candidates retrieved across hops" do
      hops = ["again", "DONE"]
      reasoner = ->(_q, _acc, _hop) { hops.shift }
      ctx = engine.iterative_retrieve("capital of France", reasoner: reasoner, max_hops: 3, max_tokens: 500)
      expect(ctx.scan("France capital is Paris").size).to eq(1)
    end
  end
end
