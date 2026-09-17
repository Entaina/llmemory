# frozen_string_literal: true

require "tmpdir"
require File.expand_path("../../../benchmarks/local/runners/run", __dir__)

RSpec.describe LocalBenchmark::Runners::Run do
  before { Llmemory.reset_configuration! }

  it "runs fixture smoke with deterministic reader" do
    out = File.join(Dir.tmpdir, "llmemory_bench_#{Process.pid}.json")
    report = described_class.new([
      "--bench", "fixtures",
      "--limit", "3",
      "--reader", "deterministic",
      "--skip-health",
      "--out", out
    ]).run!

    expect(report[:queries]).to eq(3)
    expect(File).to exist(out)
    FileUtils.rm_f(out)
  end

  it "runs fixture smoke with hybrid variant" do
    out = File.join(Dir.tmpdir, "llmemory_bench_hybrid_#{Process.pid}.json")
    report = described_class.new([
      "--bench", "fixtures",
      "--limit", "2",
      "--variant", "hybrid",
      "--reader", "deterministic",
      "--skip-health",
      "--out", out
    ]).run!

    expect(report[:variant]).to eq(:hybrid)
    expect(report[:queries]).to eq(2)
    FileUtils.rm_f(out)
  end
end
