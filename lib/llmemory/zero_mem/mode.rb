# frozen_string_literal: true

module Llmemory
  module ZeroMem
    module Mode
      MODES = %i[classic zero_mem hybrid].freeze

      module_function

      def valid?(mode)
        MODES.include?(mode.to_sym)
      end

      def normalize(mode)
        sym = (mode || :classic).to_sym
        raise Llmemory::ConfigurationError, "invalid memory_mode: #{mode.inspect}" unless valid?(sym)

        sym
      end

      def zero_mem_enabled?(mode)
        %i[zero_mem hybrid].include?(normalize(mode))
      end

      def zero_mem_strict?(mode)
        normalize(mode) == :zero_mem
      end
    end
  end
end
