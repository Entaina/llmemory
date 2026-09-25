# frozen_string_literal: true

require File.expand_path("../../../benchmarks/local/harness", __dir__)

RSpec.describe LocalBenchmark::Harness do
  let(:conversation) do
    {
      "id" => "conv_test",
      "sessions" => [{ "turns" => [{ "id" => "t1", "role" => "user", "content" => "Hello" }] }],
      "queries" => [{ "id" => "q1", "text" => "Hello?", "gold_answer" => "Hello" }]
    }
  end

  before { Llmemory.reset_configuration! }

  it "builds hybrid memory with memory_mode :hybrid" do
    harness = described_class.new(variant: :hybrid, reader: ZeroMemBenchmark::Reader.new)
    memory = harness.send(:build_memory, conversation)
    expect(memory.memory_mode).to eq(:hybrid)
    expect(memory.trace_store).not_to be_nil
  end
end
