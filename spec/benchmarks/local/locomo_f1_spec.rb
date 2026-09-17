# frozen_string_literal: true

require File.expand_path("../../../benchmarks/local/scorers/locomo_f1", __dir__)

RSpec.describe LocalBenchmark::Scorers::LoCoMoF1 do
  it "scores single-hop with token overlap" do
    score = described_class.locomo_f1(category: 4, prediction: "teal color", gold_answer: "teal")
    expect(score).to be > 0.5
  end

  it "scores adversarial abstention" do
    score = described_class.locomo_f1(category: 5, prediction: "not mentioned in the context", gold_answer: "n/a")
    expect(score).to eq(1.0)
  end
end
