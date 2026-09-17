# frozen_string_literal: true

module ZeroMemBenchmark
  module Variants
    DEFINITIONS = {
      classic: { mode: :classic },
      zero_mem_full: { mode: :zero_mem },
      hierarchy_only: { mode: :zero_mem, fusion_weights: { graph: 0.0, hierarchy: 1.0 } },
      graph_only: { mode: :zero_mem, fusion_weights: { graph: 1.0, hierarchy: 0.0 } },
      no_closure: { mode: :zero_mem, skip_closure: true },
      no_calibration: { mode: :zero_mem, skip_calibration: true },
      no_planning: { mode: :zero_mem, fusion_weights: { graph: 0.5, hierarchy: 0.5 } }
    }.freeze

    module_function

    def keys
      DEFINITIONS.keys
    end

    def fetch(key)
      DEFINITIONS.fetch(key.to_sym)
    end

    def zero_mem?(key)
      fetch(key)[:mode] == :zero_mem
    end
  end
end
