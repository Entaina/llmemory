#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require File.expand_path("../scorers/context_hit", __dir__)
require File.expand_path("../report", __dir__)

path = ARGV[0]
unless path && File.file?(path)
  warn "Usage: bundle exec ruby benchmarks/local/scripts/rescore_context.rb PATH.json"
  exit 1
end

data = JSON.parse(File.read(path), symbolize_names: true)
rows = Array(data[:rows])

rows.each do |row|
  row[:context_hit] = LocalBenchmark::Scorers::ContextHit.from_row(row)
end

agg = LocalBenchmark::Report.context_hit_aggregate(rows)
puts "File: #{path}"
puts "Queries: #{rows.size}"
puts "context_hit mean: #{agg[:mean].nil? ? 'n/a' : format('%.4f', agg[:mean])} (#{agg[:count]} scored, #{agg[:not_applicable]} n/a)"

if ENV["LLMEMORY_RESCORE_WRITE"]
  data[:rows] = rows
  data[:context_rescore] = {
    context_hit: agg,
    rescored_at: Time.now.utc.iso8601
  }
  File.write(path, JSON.pretty_generate(data))
  puts "Updated #{path} (LLMEMORY_RESCORE_WRITE=1)"
end
