# frozen_string_literal: true

module Llmemory
  module ZeroMem
    module Mode
      MODE = :hybrid

      module_function

      def valid?(mode)
        mode.to_sym == MODE
      end

      def normalize(mode)
        sym = (mode || MODE).to_sym
        raise Llmemory::ConfigurationError, "invalid memory_mode: #{mode.inspect}" unless valid?(sym)

        sym
      end

      def zero_mem_enabled?(_mode = MODE)
        true
      end

      def zero_mem_strict?(_mode = MODE)
        false
      end
    end
  end
end
