# frozen_string_literal: true

# One-off diagnostic: why LoCoMo retrieval/answers fail. Not part of gem API.
require "json"
require "llmemory"
require File.expand_path("../zero_mem/harness", __dir__)
require_relative "adapters/locomo"
require_relative "harness"
require_relative "reader_llm"

conv = LocalBenchmark::Adapters::LoCoMo.new.conversations(limit: 1).first
query = conv["queries"].first
puts "=== Query ==="
puts query["text"]
puts "gold: #{query['gold_answer']} evidence: #{query['gold_trace_ids'].inspect}"

turns = ZeroMem::FixtureLoader.turns_by_id(conv)
gold_turn = turns[query["gold_trace_ids"].first]
puts "\n=== Gold turn ==="
puts gold_turn["content"]

%i[classic zero_mem_full hybrid].each do |variant|
  puts "\n========== variant #{variant} =========="
  harness = LocalBenchmark::Harness.new(variant: variant, reader: ZeroMemBenchmark::Reader.new)
  memory = harness.send(:build_memory, conv)
  if variant == :zero_mem_full
    harness.send(:hydrate!, memory, conv)
  else
    harness.send(:hydrate_and_consolidate_per_session!, memory, conv)
  end

  if variant != :zero_mem_full
    lt = memory.instance_variable_get(:@long_term)
    storage = lt.instance_variable_get(:@storage)
    items = storage.get_all_items(memory.user_id) rescue storage.search_items(memory.user_id, "Caroline LGBTQ")
    resources = storage.get_all_resources(memory.user_id) rescue []
    puts "stored items: #{items.size}, resources: #{resources.size}"
    items.first(5).each { |i| puts "  item: #{i[:content] || i['content']}" }
  end

  ctx = if variant == :zero_mem_full
          ev = memory.retrieve_evidence(query["text"], max_tokens: 2000)
          puts "evidence traces: #{ev.evidence.size}"
          ev.evidence.first(5).each do |e|
            snippet = e.content.to_s.gsub(/\s+/, " ")[0, 120]
            puts "  trace #{e.trace_id}: #{snippet}"
          end
          ev.to_context
        else
          memory.retrieve(query["text"], max_tokens: 2000)
        end

  ctx_str = ctx.to_s
  puts "context chars: #{ctx_str.length}"
  puts "context snippet: #{ctx_str.gsub(/\s+/, ' ')[0, 400]}"

  gold_in_ctx = gold_turn["content"].downcase.split.first(3).all? { |w| ctx_str.downcase.include?(w) }
  puts "gold turn (partial) in context? #{gold_in_ctx}"

  ranked = if variant == :zero_mem_full
             harness.send(:rank_fixture_turn_ids, memory.retrieve_evidence(query["text"], max_tokens: 2000), query)
           else
             harness.send(:rank_trace_ids_in_context, ctx_str, turns, query)
           end
  puts "ranked ids (first 10): #{ranked.first(10).inspect}"
  puts "gold in ranked top 5? #{ranked.first(5).intersect?(query['gold_trace_ids'])}"
end
