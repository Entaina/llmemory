# frozen_string_literal: true

require "json"
require "fileutils"
require "optparse"
require "llmemory"

require_relative "../lm_studio"
require_relative "../reader_llm"
require_relative "../harness"
require_relative "../registry"
require_relative "../report"
require_relative "../sampler"
require_relative "../caching_client"
require_relative "../bench_trace"

module LocalBenchmark
  module Runners
    class Run
      DEFAULT_OUT = File.expand_path("../results/run.json", __dir__)

      def self.run!(argv = ARGV)
        new(argv).run!
      rescue Llmemory::LLMError => e
        warn "Bench run failed (LLM): #{e.message}"
        exit 1
      end

      def initialize(argv)
        @options = {
          bench: "fixtures",
          variant: :classic,
          limit: nil,
          out: ENV.fetch("LLMEMORY_BENCH_OUT", DEFAULT_OUT),
          skip_health: false,
          reader: :deterministic,
          use_judge: false,
          conversations: nil,
          per_conversation: nil,
          seed: ENV["LLMEMORY_BENCH_SEED"],
          stratify: nil
        }
        parse!(argv)
      end

      def run!
        profile_meta = LmStudio.apply_profile! unless @options[:reader] == :deterministic
        adapter = Registry.build(@options[:bench])
        unless adapter.available?
          warn "Skipping: #{adapter.skip_reason}"
          exit 0
        end

        LmStudio.health_check! unless @options[:skip_health] || @options[:reader] == :deterministic

        raw = adapter.conversations(limit: nil)
        sampled = Sampler.sample(
          raw,
          bench: @options[:bench],
          limit: @options[:limit],
          conversations_limit: @options[:conversations],
          per_conversation: @options[:per_conversation],
          seed: @options[:seed],
          stratify: @options[:stratify]
        )
        conversations = sampled[:conversations]
        if BenchTrace.enabled?
          BenchTrace.log(
            "run bench=#{@options[:bench]} variant=#{@options[:variant]} " \
            "conversations=#{conversations.size} sampling=#{sampled[:sampling]&.inspect}"
          )
        end
        reader = build_reader
        llm = if @options[:reader] == :deterministic
                nil
              else
                LocalBenchmark::CachingClient.wrap!(cache_reader: false)
              end

        harness = LocalBenchmark::Harness.new(
          variant: @options[:variant],
          llm: llm,
          reader: reader
        )
        report = harness.run!(conversations: conversations)
        report = Report.enrich(report, bench: @options[:bench], use_judge: @options[:use_judge])
        report[:lm_studio] = profile_meta if profile_meta
        report[:generated_at] = Time.now.utc.iso8601
        report[:sampling] = sampled[:sampling]

        FileUtils.mkdir_p(File.dirname(@options[:out]))
        File.write(@options[:out], JSON.pretty_generate(report))
        puts "Wrote #{@options[:out]} (#{report[:queries]} queries, bench=#{@options[:bench]})"
        report
      end

      private

      def parse!(argv)
        OptionParser.new do |opts|
          opts.banner = "Usage: bundle exec ruby benchmarks/local/runners/run.rb [options]"
          opts.on("--bench NAME", "Benchmark id (#{Registry::BENCHES.keys.join(', ')})") { |v| @options[:bench] = v }
          opts.on("--variant NAME", "classic|zero_mem_full|...") { |v| @options[:variant] = v.to_sym }
          opts.on("--limit N", Integer, "Max queries (smoke)") { |v| @options[:limit] = v }
          opts.on("--conversations N", Integer, "Stratified sample: number of conversations") { |v| @options[:conversations] = v }
          opts.on("--per-conversation Q", Integer, "Stratified sample: queries per conversation") { |v| @options[:per_conversation] = v }
          opts.on("--seed S", "Deterministic sampling seed") { |v| @options[:seed] = v }
          opts.on("--stratify FIELD", "category|question_type") { |v| @options[:stratify] = v }
          opts.on("--out PATH", "Output JSON path") { |v| @options[:out] = v }
          opts.on("--reader MODE", "deterministic|llm") { |v| @options[:reader] = v.to_sym }
          opts.on("--use-judge", "Run local LLM judge (extra tokens)") { @options[:use_judge] = true }
          opts.on("--skip-health", "Skip LM Studio /v1/models check") { @options[:skip_health] = true }
        end.parse!(argv)
      end

      def build_reader
        case @options[:reader]
        when :llm
          ReaderLLM.new.to_reader
        else
          ZeroMemBenchmark::Reader.new
        end
      end
    end
  end
end

LocalBenchmark::Runners::Run.run! if $PROGRAM_NAME == __FILE__
