# frozen_string_literal: true

require "json"

dir = ARGV[0] || "benchmarks/local/results"
pattern = ARGV[1] || "*__hybrid__step_*.json"
paths = Dir.glob(File.join(dir, pattern)).sort_by { |p| File.mtime(p) }
abort("No files matching #{File.join(dir, pattern)}") if paths.empty?

rows = paths.map do |path|
  data = JSON.parse(File.read(path))
  scores = data["bench_scores"] || {}
  primary = scores.values.find { |v| v.is_a?(Hash) && v.key?("mean") }
  mean = primary ? primary["mean"] : scores.values.compact.first
  {
    file: File.basename(path),
    bench: data["bench"],
    queries: data["queries"],
    scores: scores,
    primary_mean: mean
  }
end

puts "hybrid step cycle (#{rows.size} runs)"
puts
rows.each do |r|
  puts "#{r[:bench].ljust(18)} Q=#{r[:queries].to_s.ljust(3)} primary=#{r[:primary_mean].inspect} #{r[:file]}"
end

out = File.join(dir, "step_cycle_summary_#{Time.now.utc.strftime('%Y%m%dT%H%M%SZ')}.json")
File.write(out, JSON.pretty_generate(generated_at: Time.now.utc.iso8601, runs: rows))
puts
puts "Wrote #{out}"
