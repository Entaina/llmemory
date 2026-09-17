# frozen_string_literal: true

require File.expand_path("../../../spec/support/zero_mem/fixture_loader", __dir__)
require_relative "base"

module LocalBenchmark
  module Adapters
    class Fixtures < Base
      def available?
        true
      end

      def each_conversation
        return enum_for(:each_conversation) unless block_given?

        ZeroMem::FixtureLoader.validate_coverage!.each do |conv|
          enriched = conv.merge("consolidate_after_hydrate" => true)
          yield enriched
        end
      end
    end
  end
end
