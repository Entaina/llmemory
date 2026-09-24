# frozen_string_literal: true

require "json"
require "open3"

RSpec.describe "summarize_run.rb" do
  let(:script) { File.expand_path("../../../benchmarks/local/scripts/summarize_run.rb", __dir__) }

  it "prints answer.f1 and skips retrieval misses for mem2act" do
    payload = {
      "bench" => "mem2act",
      "variant" => "hybrid",
      "queries" => 1,
      "bench_scores" => { "param_f1" => { "mean" => 0.5, "count" => 1 } },
      "rows" => [
        {
          "conversation_id" => "qa_1",
          "query_id" => "q1",
          "question_type" => "tool_call",
          "metadata" => { "tool_name" => "Search" },
          "retrieval_hit" => false,
          "prediction" => '{"name":"Search"}',
          "gold_answer" => "{}",
          "answer" => { "f1" => 0.0 }
        }
      ]
    }
    require "tmpdir"
    path = File.join(Dir.tmpdir, "summarize_run_spec_#{Process.pid}.json")
    File.write(path, JSON.generate(payload))
    out, status = Open3.capture2("ruby", script, path)
    expect(status.success?).to be(true)
    expect(out).not_to include("retrieval misses")
  ensure
    File.delete(path) if path && File.file?(path)
  end
end
