# frozen_string_literal: true

# Aggregate per-bench variant JSON files from suite-diag into one comparison report.
require "json"

module SuiteDiagHelpers
  module_function

  def category_f1_for(bench, rows)
    return {} unless bench.to_s == "locomo"

    by_cat = Hash.new { |h, k| h[k] = [] }
    rows.each do |row|
      cat = row["category"] || row[:category]
      f1 = row.dig("answer", "f1") || row.dig(:answer, :f1)
      next if f1.nil?

      by_cat[cat] << f1.to_f
    end
    by_cat.transform_values { |vals| vals.sum / vals.size }
  end

  def hits_converted_rate(rows, bench)
    scored = rows.filter_map do |row|
      hit = row["retrieval_hit"]
      hit = row[:retrieval_hit] if hit.nil?
      next unless hit == true

      f1 = row.dig("answer", "f1") || row.dig(:answer, :f1)
      em = row.dig("answer", "exact_match") || row.dig(:answer, :exact_match)
      judge = row.dig("llm_judge") || row["llm_judge"]
      case bench.to_s
      when "locomo"
        f1.to_f > 0.2
      when "longmemeval", "memoryagentbench", "groupmembench"
        em.to_f.positive? || judge.to_f.positive?
      else
        f1.to_f > 0.2
      end
    end
    hits = rows.count { |r| r["retrieval_hit"] == true || r[:retrieval_hit] == true }
    return nil if hits.zero?

    { rate: scored.count(true).to_f / hits, hits: hits, converted: scored.count(true) }
  end

  def build_comparisons(runs)
    by_bench = runs.group_by { |r| r[:bench] }
    by_bench.flat_map do |bench, bench_runs|
      classic = bench_runs.find { |r| r[:variant] == "classic" }
      zm = bench_runs.find { |r| r[:variant] == "zero_mem_full" }
      hybrid = bench_runs.find { |r| r[:variant] == "hybrid" }
      next [] unless hybrid

      primary_metric = bench == "locomo" ? "locomo_f1" : "substring_em"
      {
        bench: bench,
        hybrid_vs_classic: delta_metrics(hybrid, classic, primary_metric),
        hybrid_vs_zero_mem: delta_metrics(hybrid, zm, primary_metric)
      }
    end
  end

  def delta_metrics(hybrid, other, primary_key)
    return { status: "missing_baseline" } unless hybrid && other

    h_scores = hybrid[:bench_scores] || {}
    o_scores = other[:bench_scores] || {}
    {
      primary_delta: metric_mean(h_scores[primary_key]) - metric_mean(o_scores[primary_key]),
      retrieval_hit_delta: (hybrid[:retrieval_hit_mean].to_f - other[:retrieval_hit_mean].to_f),
      recall_at_5_delta: (hybrid[:recall_at_5_mean].to_f - other[:recall_at_5_mean].to_f),
      judge_delta: judge_delta(h_scores, o_scores)
    }
  end

  def metric_mean(entry)
    return nil unless entry.is_a?(Hash)

    (entry["mean"] || entry[:mean]).to_f
  end

  def judge_delta(h_scores, o_scores)
    h = metric_mean(h_scores["llm_judge"])
    o = metric_mean(o_scores["llm_judge"])
    return nil if h.nil? || o.nil?

    h - o
  end

  def detect_regressions(comparisons)
    comparisons.flat_map do |cmp|
      %i[hybrid_vs_classic hybrid_vs_zero_mem].filter_map do |key|
        deltas = cmp[key]
        next unless deltas.is_a?(Hash)

        primary = deltas[:primary_delta]
        next if primary.nil?
        next unless primary.negative?

        { bench: cmp[:bench], comparison: key, primary_delta: primary }
      end
    end
  end
end

results_dir = ARGV[0] || "benchmarks/local/results"
timestamp_arg = ARGV[1]
abort("Usage: suite_diag.rb RESULTS_DIR TIMESTAMP [TIMESTAMP2 ...]") if timestamp_arg.to_s.empty?

timestamps = ARGV[1..].flat_map { |t| t.split(",") }.map(&:strip).reject(&:empty?)
paths = []
timestamps.each do |timestamp|
  pattern = File.join(results_dir, "*__*__#{timestamp}.json")
  paths.concat(Dir.glob(pattern))
end
paths = paths.uniq.reject { |p| File.basename(p).start_with?("suite_diag_") }
paths.sort!

summary = {
  generated_at: Time.now.utc.iso8601,
  timestamps: timestamps,
  runs: [],
  comparisons: [],
  regressions: []
}

paths.each do |path|
  data = JSON.parse(File.read(path))
  loc = data.dig("means", "localization") || {}
  rows = Array(data["rows"])
  invoke_calls = rows.map { |r| r.dig("cost", "invoke_calls_delta") }.compact
  run_entry = {
    bench: data["bench"],
    variant: data["variant"],
    path: path,
    queries: data["queries"],
    bench_scores: data["bench_scores"],
    retrieval_hit_mean: data.dig("bench_scores", "retrieval_hit", "mean"),
    recall_at_5_mean: loc["recall@5"] || loc["recall_at_5"],
    invoke_calls_delta_mean: invoke_calls.empty? ? nil : (invoke_calls.sum.to_f / invoke_calls.size),
    status: data["queries"].to_i.positive? ? "ok" : "missing",
    sampling: data["sampling"],
    category_f1: SuiteDiagHelpers.category_f1_for(data["bench"], rows)
  }
  run_entry[:hits_converted] = SuiteDiagHelpers.hits_converted_rate(rows, data["bench"])
  summary[:runs] << run_entry
end

summary[:comparisons] = SuiteDiagHelpers.build_comparisons(summary[:runs])
summary[:regressions] = SuiteDiagHelpers.detect_regressions(summary[:comparisons])

label = timestamps.size == 1 ? timestamps.first : timestamps.join("_")
out = File.join(results_dir, "suite_diag_#{label}.json")
File.write(out, JSON.pretty_generate(summary))
puts "Wrote #{out} (#{summary[:runs].size} runs, #{summary[:regressions].size} regressions flagged)"
