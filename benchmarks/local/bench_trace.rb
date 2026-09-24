# frozen_string_literal: true

module LocalBenchmark
  module BenchTrace
    module_function

    def enabled?
      ENV["LLMEMORY_BENCH_TRACE"] == "1"
    end

    def log(message)
      return unless enabled?

      ts = Time.now.utc.strftime("%H:%M:%S.%L")
      line = "[bench-trace #{ts}] #{message}"
      warn line
      path = ENV["LLMEMORY_BENCH_TRACE_FILE"].to_s
      return if path.empty?

      File.open(path, "a") { |f| f.puts line }
    rescue StandardError
      nil
    end

    def measure(label)
      return yield unless enabled?

      t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = yield
      ms = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0) * 1000.0
      log("#{label} #{ms.round(1)}ms")
      result
    end

    def invoke_calls_delta(before, after)
      bucket_delta(before, after, :invoke, :calls)
    end

    def embed_calls_delta(before, after)
      bucket_delta(before, after, :embed, :calls)
    end

    def bucket_delta(before, after, bucket, key)
      b = (before[bucket] || before[bucket.to_s] || {})
      a = (after[bucket] || after[bucket.to_s] || {})
      (a[key] || a[key.to_s] || 0).to_i - (b[key] || b[key.to_s] || 0).to_i
    end
  end
end
