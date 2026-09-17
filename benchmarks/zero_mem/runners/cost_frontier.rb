# frozen_string_literal: true

require_relative "ablation"
require "json"
require "fileutils"

module ZeroMemBenchmark
  module Runners
    class CostFrontier
      DEFAULT_OUT = File.expand_path("../results/cost_frontier.json", __dir__)

      def self.run!(ablation_path: ENV.fetch("ZEROMEM_ABLATION_OUT", Ablation::DEFAULT_OUT),
                    out_path: ENV.fetch("ZEROMEM_COST_OUT", DEFAULT_OUT))
        unless File.file?(ablation_path)
          ablation = Ablation.run!(out_path: ablation_path)
        else
          ablation = JSON.parse(File.read(ablation_path), symbolize_names: true)
        end

        points = Array(ablation[:variants]).map do |rep|
          {
            variant: rep[:variant],
            recall_at_5: rep.dig(:means, :localization, :"recall@5"),
            latency_ms: rep.dig(:means, :latency_ms)
          }
        end
        payload = {
          generated_at: Time.now.utc.iso8601,
          points: points,
          note: "Utility-latency frontier from fixture ablation; not comparable to published Zero-Mem paper numbers."
        }
        FileUtils.mkdir_p(File.dirname(out_path))
        File.write(out_path, JSON.pretty_generate(payload))
        puts "Wrote #{out_path}"
        payload
      end
    end
  end
end

ZeroMemBenchmark::Runners::CostFrontier.run! if $PROGRAM_NAME == __FILE__
