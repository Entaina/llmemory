# frozen_string_literal: true

require "json"

path = ARGV[0]
query_id = ARGV[1]
abort("Usage: explain_row.rb RESULT.json QUERY_ID") if path.to_s.empty? || query_id.to_s.empty?

data = JSON.parse(File.read(path))
rows = Array(data["rows"])
row = rows.find { |r| r["query_id"] == query_id || r[:query_id] == query_id }
abort("Query #{query_id} not found") unless row

row = row.transform_keys(&:to_sym) if row.is_a?(Hash)

puts "=== #{row[:query_id]} ==="
puts "Q: #{row[:query_text]}"
puts "Gold: #{row[:gold_answer]}"
puts "Pred: #{row[:prediction]}"
puts "Retrieval hit: #{row[:retrieval_hit]}"
puts "F1: #{row.dig(:answer, :f1) || row.dig('answer', 'f1')}"
puts
puts "--- Context ---"
puts row[:context] || row["context"]
puts
if (ids = row[:ranked_trace_ids] || row["ranked_trace_ids"]).is_a?(Array) && ids.any?
  puts "--- Ranked trace ids ---"
  puts ids.join(", ")
end
if (fused = row[:fused_items] || row["fused_items"]).is_a?(Array) && fused.any?
  puts "--- Fused items ---"
  fused.each { |f| puts f.inspect }
end
if (stats = row[:memory_stats] || row["memory_stats"])
  puts "--- Memory stats ---"
  puts JSON.pretty_generate(stats)
end
