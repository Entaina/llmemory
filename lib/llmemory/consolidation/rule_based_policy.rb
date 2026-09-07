# frozen_string_literal: true

module Llmemory
  module Consolidation
    # Rule-based consolidation policy for agents with authoritative live data sources
    # (tools, DB snapshots). Drops or marks volatile facts that should not be treated
    # as stable long-term memory.
    #
    # Precedence (first match wins):
    #   1. drop_if callable
    #   2. volatile_if callable
    #   3. drop_predicates (graph relations)
    #   4. volatile_predicates (graph relations)
    #   5. drop_categories (file-based items)
    #   6. volatile_categories (file-based items)
    #   7. :keep
    class RuleBasedPolicy < Policy
      def initialize(
        drop_predicates: [],
        volatile_predicates: [],
        drop_categories: [],
        volatile_categories: [],
        drop_if: nil,
        volatile_if: nil
      )
        @drop_predicates = normalize_list(drop_predicates)
        @volatile_predicates = normalize_list(volatile_predicates)
        @drop_categories = normalize_list(drop_categories)
        @volatile_categories = normalize_list(volatile_categories)
        @drop_if = drop_if
        @volatile_if = volatile_if
      end

      def decide(unit)
        return :drop if callable_true?(@drop_if, unit)
        return :volatile if callable_true?(@volatile_if, unit)

        case unit.kind
        when :relation
          predicate = Unit.normalize_predicate(unit.predicate)
          return :drop if @drop_predicates.include?(predicate)
          return :volatile if @volatile_predicates.include?(predicate)
        when :item
          category = Unit.normalize_category(unit.category)
          return :drop if @drop_categories.include?(category)
          return :volatile if @volatile_categories.include?(category)
        end

        :keep
      end

      private

      def normalize_list(values)
        Array(values).map { |value| value.to_s.strip.downcase.gsub(/\s+/, "_") }.reject(&:empty?)
      end

      def callable_true?(callable, unit)
        callable.respond_to?(:call) && callable.call(unit) == true
      end
    end
  end
end
