# frozen_string_literal: true

require_relative "../consolidation/unit"
require_relative "../consolidation/filter"

module Llmemory
  module Maintenance
    # Archives long-term facts that the current consolidation policy would drop.
    # Useful for cleaning legacy data consolidated before a policy was configured.
    class PolicyPrune
      Result = Struct.new(:graph_edges, :file_items, :dry_run, keyword_init: true) do
        def total
          graph_edges + file_items
        end

        def to_h
          { graph_edges: graph_edges, file_items: file_items, dry_run: dry_run, total: total }
        end
      end

      def initialize(dry_run: false, policy: nil)
        @dry_run = dry_run
        @policy = policy || Llmemory.configuration.consolidation_policy
      end

      def run(memory:)
        case memory
        when LongTerm::GraphBased::Memory
          Result.new(graph_edges: prune_graph(memory), file_items: 0, dry_run: @dry_run)
        when LongTerm::FileBased::Memory
          Result.new(graph_edges: 0, file_items: prune_file(memory), dry_run: @dry_run)
        else
          raise ArgumentError, "Unsupported memory type: #{memory.class}"
        end
      end

      private

      def prune_graph(memory)
        storage = memory.instance_variable_get(:@graph_storage)
        kg = memory.instance_variable_get(:@kg)
        user_id = memory.user_id
        return 0 unless storage.respond_to?(:list_edges)

        removed = 0
        storage.list_edges(user_id).each do |edge|
          next if edge.archived?

          subject = kg.find_node_by_id(edge.subject_id)
          object = kg.find_node_by_id(edge.target_id)
          unit = Consolidation::Unit.from_relation(
            subject: subject&.name,
            predicate: edge.predicate,
            object: object&.name
          )
          next unless @policy.decide(unit) == :drop

          removed += 1
          next if @dry_run

          memory.forget(ids: [edge.id], reason: "consolidation_policy_prune")
        end
        removed
      end

      def prune_file(memory)
        storage = memory.instance_variable_get(:@storage)
        user_id = memory.user_id
        removed = 0

        storage.get_all_items(user_id).each do |item|
          unit = Consolidation::Unit.from_item(item, category: item[:category] || item["category"])
          next unless @policy.decide(unit) == :drop

          item_id = item[:id] || item["id"]
          removed += 1
          next if @dry_run

          memory.forget(ids: [item_id], reason: "consolidation_policy_prune")
        end
        removed
      end
    end
  end
end
