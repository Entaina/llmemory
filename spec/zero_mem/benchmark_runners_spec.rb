# frozen_string_literal: true

require File.expand_path("../../benchmarks/zero_mem/runners/ablation", __dir__)
require File.expand_path("../../benchmarks/zero_mem/adapters/locomo", __dir__)

RSpec.describe "Zero-Mem benchmark runners" do
  describe ZeroMemBenchmark::Runners::Ablation do
    it "compares full variant against ablations" do
      full = { variant: :zero_mem_full, means: { localization: { :"recall@5" => 0.8 } } }
      other = { variant: :classic, means: { localization: { :"recall@5" => 0.5 } } }
      cmp = described_class.compare([other, full])
      expect(cmp[:classic][:recall_at_5_delta]).to eq(0.3)
    end
  end

  describe ZeroMemBenchmark::Adapters::LoCoMo do
    it "skips when dataset root is missing" do
      adapter = described_class.new(root: "")
      expect(adapter.available?).to be(false)
      expect { adapter.each_conversation { |_| raise "nope" } }.not_to raise_error
    end
  end
end
