# frozen_string_literal: true

RSpec.describe Llmemory::ZeroMem::PageRank do
  it "converges on a small graph with known reset" do
    graph = {
      "a" => %w[b],
      "b" => %w[c],
      "c" => %w[a]
    }
    reset = { "a" => 1.0 }
    ranks = described_class.new(gamma: 0.6).run(graph, reset)
    expect(ranks.values.sum).to be_within(0.01).of(1.0)
    expect(ranks["a"]).to be > ranks["c"]
  end
end
