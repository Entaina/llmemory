# frozen_string_literal: true

RSpec.describe Llmemory::Retrieval::HybridResult do
  it "keeps a later sentence that covers a query token the first hit missed" do
    profile = Llmemory::ZeroMem::QueryProfiler.new.profile("Who was the Norse leader?")
    filler = "The Mongol force invaded southern China and the campaign continued. " * 12
    text = "#{filler}A Norse-speaking ruling class settled in the region. #{filler}Their leader Rollo swore fealty to the king."
    result = described_class.new(
      items: [{ kind: :trace, text: text, score: 1.0, trace_id: "t1" }],
      profile: profile
    )

    context = result.to_context
    expect(context).to include("Norse-speaking")
    expect(context).to include("leader Rollo")
  end

  it "keeps a later sentence that names an entity the query-matching sentences omit" do
    profile = Llmemory::ZeroMem::QueryProfiler.new.profile(
      "Which text summarization system should I choose for quarterly finance reports?"
    )
    lead = "The search covers text summarization systems for quarterly finance reports. " * 8
    text = "#{lead}Model Boreal preserved numerical claims in the quarterly finance reports."
    result = described_class.new(
      items: [{ kind: :trace, text: text, score: 1.0, trace_id: "t1" }],
      profile: profile
    )

    expect(result.to_context).to include("Boreal")
  end

  it "keeps the sentence that covers the question's rare terms" do
    profile = Llmemory::ZeroMem::QueryProfiler.new.profile(
      "What did Borges say about the center and circumference of the Library?"
    )
    preamble = "The Library of Babel by Borges explores language and reality. " * 8
    quote = 'Borges notes, "The Library is a sphere whose exact center is any one of its hexagons and whose circumference is inaccessible."'
    result = described_class.new(
      items: [{ kind: :trace, text: "#{preamble}#{quote}", score: 1.0, trace_id: "t1" }],
      profile: profile
    )

    expect(result.to_context).to include("circumference")
  end

  it "puts the witness trace ahead of a fact that names a different date" do
    profile = Llmemory::ZeroMem::QueryProfiler.new.profile(
      "What is the deadline for Reporting to validate the standard? (YYYY-MM-DD)"
    )
    result = described_class.new(
      items: [
        { kind: :fact, text: "The framework must be finalized by 2025-07-19.", score: 0.9, id: "f1" },
        {
          kind: :trace,
          text: "Reporting can validate fit against the same standard before July 18 (2025-07-18).",
          score: 0.4,
          trace_id: "t1"
        }
      ],
      profile: profile
    )

    context = result.to_context
    expect(context.index("July 18")).to be < context.index("2025-07-19")
  end

  it "keeps a fact ahead of its trace when the fact quotes the same name" do
    profile = Llmemory::ZeroMem::QueryProfiler.new.profile("What kayak did the user buy?")
    result = described_class.new(
      items: [
        { kind: :fact, text: "User owns a blue kayak named Nimbus", score: 0.5, id: "f1" },
        { kind: :trace, text: "I bought a blue kayak named Nimbus.", score: 0.9, trace_id: "t1" }
      ],
      profile: profile
    )

    context = result.to_context
    expect(context.index("named Nimbus")).to be < context.index("bought a blue kayak")
  end

  it "puts the witness trace ahead of a preference fact that names someone else" do
    profile = Llmemory::ZeroMem::QueryProfiler.new.profile(
      "Which text summarization system preserved numerical claims in the quarterly finance reports?"
    )
    result = described_class.new(
      items: [
        { kind: :fact, text: "User generally prefers Model Atlas for text summarization.", score: 0.95, id: "f1" },
        {
          kind: :trace,
          text: "Model Boreal preserved numerical claims in the quarterly finance reports.",
          score: 0.3,
          trace_id: "t1"
        }
      ],
      profile: profile
    )

    context = result.to_context
    expect(context.index("Boreal")).to be < context.index("Atlas")
  end
end
