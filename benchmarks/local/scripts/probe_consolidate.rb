# frozen_string_literal: true

# One-shot: time a single consolidate-style LLM extract (same path as LoCoMo per_session).
require "llmemory"
require_relative "../lm_studio"
require_relative "../caching_client"

ENV["LLMEMORY_BENCH_TRACE"] = "1"
LmStudio.apply_profile!
LmStudio.health_check!

sample_path = ARGV[0]
abort("Usage: probe_consolidate.rb [conversation.txt]") unless sample_path && File.file?(sample_path)

text = File.read(sample_path)
storage = Llmemory::LongTerm::FileBased::Storages::MemoryStorage.new
llm = LocalBenchmark::CachingClient.wrap!
lt = Llmemory::LongTerm::FileBased::Memory.new(user_id: "probe", storage: storage, llm: llm)

t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
lt.memorize(text)
elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
stats = lt.stats
puts "memorize done in #{elapsed.round(2)}s stats=#{stats.inspect}"
