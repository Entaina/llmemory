# frozen_string_literal: true

require File.expand_path("../../../benchmarks/local/sampler", __dir__)

RSpec.describe LocalBenchmark::Sampler do
  let(:conversations) do
    [
      {
        "id" => "c1",
        "queries" => (1..5).map { |cat| { "id" => "q#{cat}", "category" => cat, "text" => "q" } }
      }
    ]
  end

  it "samples LoCoMo with stratify category deterministically" do
    a = described_class.sample(
      conversations,
      bench: "locomo",
      conversations_limit: 1,
      per_conversation: 4,
      seed: "test-seed",
      stratify: "category"
    )
    b = described_class.sample(
      conversations,
      bench: "locomo",
      conversations_limit: 1,
      per_conversation: 4,
      seed: "test-seed",
      stratify: "category"
    )
    expect(a[:conversations].first["queries"].map { |q| q["id"] }).to eq(
      b[:conversations].first["queries"].map { |q| q["id"] }
    )
    expect(a[:sampling][:mode]).to eq("stratify_category")
  end
end
