# frozen_string_literal: true

require_relative "../harness"
require "json"
require "fileutils"

module ZeroMemBenchmark
  module Runners
    class Sweep
      DEFAULT_OUT = File.expand_path("../results/sweep_fixtures.json", __dir__)

      TOP_K = [1, 3, 5, 10].freeze
      RHO = [0.4, 0.5, 0.6, 0.7].freeze

      def self.run!(out_path: ENV.fetch("ZEROMEM_SWEEP_OUT", DEFAULT_OUT))
        rows = []
        TOP_K.each do |top_k|
          RHO.each do |rho|
            report = Harness.new(
              variant: :zero_mem_full,
              retrieve_opts: { top_k: top_k, fusion_weights: { graph: rho, hierarchy: 1.0 - rho } }
            ).run!
            rows << {
              top_k: top_k,
              rho: rho,
              recall_at_5: report.dig(:means, :localization, :"recall@5"),
              latency_ms: report.dig(:means, :latency_ms)
            }
          end
        end
        payload = { generated_at: Time.now.utc.iso8601, rows: rows, best: rows.max_by { |r| r[:recall_at_5].to_f } }
        FileUtils.mkdir_p(File.dirname(out_path))
        File.write(out_path, JSON.pretty_generate(payload))
        puts "Wrote #{out_path} (#{rows.size} grid points)"
        payload
      end
    end
  end
end

ZeroMemBenchmark::Runners::Sweep.run! if $PROGRAM_NAME == __FILE__
