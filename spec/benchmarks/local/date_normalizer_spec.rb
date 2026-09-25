# frozen_string_literal: true

require File.expand_path("../../../benchmarks/local/scorers/date_normalizer", __dir__)

RSpec.describe LocalBenchmark::Scorers::DateNormalizer do
  describe ".quoted_core_mentioned?" do
    it "matches when context paraphrases the attribution but keeps the quoted claim" do
      gold = "According to Borges, 'The Library is a sphere whose exact center is any one of its hexagons and whose circumference is inaccessible.'"
      context = <<~CTX
        Borges notes, "The Library is a sphere whose exact center is any one of its hexagons and whose circumference is inaccessible." (Borges, 1941)
      CTX

      expect(described_class.quoted_core_mentioned?(context, gold)).to be(true)
      expect(described_class.calendar_mentioned?(context, gold)).to be(true)
    end
  end
end
