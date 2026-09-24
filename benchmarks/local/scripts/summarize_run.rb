# frozen_string_literal: true

require "json"

path = ARGV[0]
abort("Usage: summarize_run.rb RESULT.json") if path.to_s.empty?

data = JSON.parse(File.read(path))
bench = data["bench"].to_s
rows = Array(data["rows"]).map { |r| r.transform_keys(&:to_sym) }

def row_key(row)
  [row[:conversation_id], row[:query_id]].join(":")
end

def score_f1(row)
  ans = row[:answer]
  return row[:f1].to_f if row.key?(:f1)
  return ans[:f1].to_f if ans.is_a?(Hash) && ans.key?(:f1)

  nil
end

def tool_call_row?(row)
  row[:question_type].to_s == "tool_call" || row.dig(:metadata, :tool_name) || row.dig(:metadata, "tool_name")
end

unique_rows = rows.each_with_object({}) { |r, h| h[row_key(r)] = r }.values

puts "bench=#{data['bench']} variant=#{data['variant']} queries=#{data['queries']}"
puts "scores: #{JSON.generate(data['bench_scores'])}"
puts "sampling: #{JSON.generate(data['sampling'])}" if data["sampling"]
out_of_range = unique_rows.count { |r| r[:evidence_in_range] == false }
puts "evidence_out_of_range: #{out_of_range}" if out_of_range.positive?
puts

unless bench == "mem2act"
  miss = unique_rows.reject { |r| r[:retrieval_hit] }
  puts "retrieval misses (#{miss.size}):"
  miss.first(8).each do |r|
    flag = r[:evidence_in_range] == false ? " [evidence>Dmax]" : ""
    puts "  #{r[:query_id]} conv=#{r[:conversation_id]} cat=#{r[:category]} hit=false#{flag} pred=#{r[:prediction].to_s[0, 60]}"
  end
end

low_f1 = unique_rows.select do |r|
  next false if tool_call_row?(r)
  next false unless r[:gold_answer]

  f1 = score_f1(r)
  f1.nil? || f1.to_f < 0.2
end
low_f1.sort_by! { |r| score_f1(r) || 0.0 }
puts
puts "low F1 (#{low_f1.size}, showing worst 8):"
low_f1.first(8).each do |r|
  f1 = score_f1(r)
  puts "  #{r[:query_id]} f1=#{f1} gold=#{r[:gold_answer].to_s[0, 50]} pred=#{r[:prediction].to_s[0, 50]}"
  puts "    explain: bundle exec ruby benchmarks/local/scripts/explain_row.rb #{path} #{r[:query_id]}"
end
