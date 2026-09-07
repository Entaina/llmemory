# frozen_string_literal: true

module Llmemory
  module Consolidation
    # Base policy: all extracted units are kept in long-term memory.
    class Policy
      DECISIONS = %i[keep drop volatile].freeze

      def decide(_unit)
        :keep
      end
    end

    class NullPolicy < Policy
    end
  end
end
