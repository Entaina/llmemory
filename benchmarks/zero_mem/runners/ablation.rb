# frozen_string_literal: true

require_relative "../harness"
require_relative "../variants"
require "json"
require "fileutils"

module ZeroMemBenchmark
  module Runners
    class Ablation
      DEFAULT_OUT = File.expand_path("../results/ablation_fixtures.json", __dir__)
      FIXTURE_VARIANTS = %i[classic zero_mem_full hierarchy_only graph_only no_closure no_calibration].freeze

      def self.run!(variants: FIXTURE_VARIANTS, out_path: ENV.fetch("ZEROMEM_ABLATION_OUT", DEFAULT_OUT))
        reports = variants.map do |variant|
          Harness.new(variant: variant).run!
        end
        payload = {
          generated_at: Time.now.utc.iso8601,
          variants: reports,
          comparison: compare(reports)
        }
        FileUtils.mkdir_p(File.dirname(out_path))
        File.write(out_path, JSON.pretty_generate(payload))
        puts "Wrote #{out_path}"
        payload
      end

      def self.compare(reports)
        full = reports.find { |r| r[:variant] == :zero_mem_full }
        return {} unless full

        full_r5 = full.dig(:means, :localization, :"recall@5").to_f
        reports.each_with_object({}) do |rep, acc|
          next if rep[:variant] == :zero_mem_full

          other = rep.dig(:means, :localization, :"recall@5").to_f
          acc[rep[:variant]] = { recall_at_5_delta: (full_r5 - other).round(4) }
        end
      end
    end
  end
end

ZeroMemBenchmark::Runners::Ablation.run! if $PROGRAM_NAME == __FILE__
