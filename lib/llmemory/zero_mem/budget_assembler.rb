# frozen_string_literal: true

module Llmemory
  module ZeroMem
    class BudgetAssembler
      RESERVE_TOKENS = 64

      def assemble(evidence, max_tokens:, local_reserve: RESERVE_TOKENS, atomic_groups: nil)
        budget = max_tokens&.to_i
        return evidence if budget.nil? || budget <= 0

        reserve = [local_reserve, budget / 4].min
        remaining = budget - reserve
        selected = []
        used_ids = {}

        groups = build_atomic_groups(evidence, atomic_groups)
        ungrouped = evidence.reject { |ev| groups.any? { |g| g.include?(ev.trace_id) } }

        groups.each do |group|
          members = group.map { |id| evidence.find { |ev| ev.trace_id == id } }.compact
          cost = members.sum { |ev| token_cost(ev) }
          next if cost > remaining

          members.each do |ev|
            selected << ev
            used_ids[ev.trace_id] = true
          end
          remaining -= cost
        end

        ungrouped.each do |ev|
          next if used_ids[ev.trace_id]

          cost = token_cost(ev)
          next if cost > remaining && !selected.empty?

          if cost <= remaining
            selected << ev
            remaining -= cost
          end
        end

        selected
      end

      def build_atomic_groups(evidence, explicit_groups)
        ids = evidence.map(&:trace_id)
        Array(explicit_groups).map do |group|
          Array(group).map(&:to_s).select { |id| ids.include?(id) }
        end.reject(&:empty?)
      end

      private

      def token_cost(evidence)
        line = "[#{evidence.trace_id}] #{evidence.role}: #{evidence.content}"
        (Llmemory::Tokenizer.tokenize(line).size + 4)
      end
    end
  end
end
