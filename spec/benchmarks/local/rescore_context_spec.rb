# frozen_string_literal: true

require "json"
require "open3"
require File.expand_path("../../../benchmarks/local/scorers/context_hit", __dir__)
require File.expand_path("../../../benchmarks/local/report", __dir__)

RSpec.describe "rescore_context.rb" do
  let(:script) { File.expand_path("../../../benchmarks/local/scripts/rescore_context.rb", __dir__) }
  let(:fixture) do
    {
      "bench" => "locomo",
      "rows" => [
        {
          "workload_class" => "locomo",
          "gold_answer" => "Paris",
          "context" => "User said they live in Paris.",
          "retrieval_hit" => true
        },
        {
          "workload_class" => "locomo",
          "gold_answer" => "Berlin",
          "context" => "No relevant facts.",
          "retrieval_hit" => false
        }
      ]
    }
  end

  it "re-scores context_hit from stored context without HTTP" do
    path = File.join("/tmp", "rescore_context_#{Process.pid}.json")
    File.write(path, JSON.generate(fixture))
    rows = fixture["rows"].map { |r| r.transform_keys(&:to_sym) }
    rows.each { |r| r[:context_hit] = LocalBenchmark::Scorers::ContextHit.from_row(r) }
    agg = LocalBenchmark::Report.context_hit_aggregate(rows)
    expect(agg[:mean]).to be_within(0.001).of(0.5)
    expect(agg[:count]).to eq(2)

    out, status = Open3.capture2("bundle", "exec", "ruby", script, path)
    expect(status).to be_success
    expect(out).to include("context_hit mean: 0.5000")
  ensure
    File.delete(path) if path && File.file?(path)
  end
end
