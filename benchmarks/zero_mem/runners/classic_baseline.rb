# frozen_string_literal: true

require_relative "../harness"
require "json"
require "fileutils"

module ZeroMemBenchmark
  module Runners
    class ClassicBaseline
      DEFAULT_OUT = File.expand_path("../results/classic_baseline.json", __dir__)

      def self.run!(out_path: ENV.fetch("ZEROMEM_BASELINE_OUT", DEFAULT_OUT))
        report = Harness.new(variant: :classic).run!
        FileUtils.mkdir_p(File.dirname(out_path))
        File.write(out_path, JSON.pretty_generate(report))
        puts "Wrote #{out_path} (#{report[:queries]} queries)"
        report
      end
    end
  end
end

ZeroMemBenchmark::Runners::ClassicBaseline.run! if $PROGRAM_NAME == __FILE__
