# frozen_string_literal: true

require "tempfile"
require File.expand_path("../../benchmarks/zero_mem/adapters/memory_data", __dir__)

RSpec.describe ZeroMemBenchmark::Adapters::MemoryData do
  it "does not perform HTTP and skips when dataset_root is missing" do
    adapter = described_class.new
    expect(adapter.available?).to be(false)
    expect(adapter.skip_reason).to include("dataset_root")
    expect { adapter.each_conversation { |_| raise "should not yield" } }.not_to raise_error
  end

  it "yields parsed conversations when a local directory exists" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "sample.json"), { id: "x", turns: [] }.to_json)
      profile = Tempfile.new(["profile", ".yml"])
      profile.write({ "memory_data" => { "dataset_root" => dir, "commit" => "test" } }.to_yaml)
      profile.close

      adapter = described_class.new(profile_path: profile.path)
      ids = adapter.each_conversation.map { |c| c["id"] }
      expect(ids).to eq(["x"])
    ensure
      profile&.unlink
    end
  end
end
