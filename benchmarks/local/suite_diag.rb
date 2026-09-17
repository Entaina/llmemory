# frozen_string_literal: true

# Aggregate per-bench variant JSON files from suite-diag into one comparison report.
require "json"

results_dir = ARGV[0] || "benchmarks/local/results"
timestamp = ARGV[1]
abort("Usage: suite_diag.rb RESULTS_DIR TIMESTAMP") if timestamp.to_s.empty?

pattern = File.join(results_dir, "*__*__#{timestamp}.json")
paths = Dir.glob(pattern).reject { |p| File.basename(p).start_with?("suite_diag_") }
paths.sort!

summary = {
  generated_at: Time.now.utc.iso8601,
  timestamp: timestamp,
  runs: []
}

paths.each do |path|
  data = JSON.parse(File.read(path))
  loc = data.dig("means", "localization") || {}
  rows = Array(data["rows"])
  invoke_calls = rows.map { |r| r.dig("cost", "invoke_calls_delta") }.compact
  summary[:runs] << {
    bench: data["bench"],
    variant: data["variant"],
    path: path,
    queries: data["queries"],
    bench_scores: data["bench_scores"],
    retrieval_hit_mean: data.dig("bench_scores", "retrieval_hit", "mean"),
    recall_at_5_mean: loc["recall@5"] || loc["recall_at_5"],
    invoke_calls_delta_mean: invoke_calls.empty? ? nil : (invoke_calls.sum.to_f / invoke_calls.size)
  }
end

out = File.join(results_dir, "suite_diag_#{timestamp}.json")
File.write(out, JSON.pretty_generate(summary))
puts "Wrote #{out} (#{summary[:runs].size} runs)"
