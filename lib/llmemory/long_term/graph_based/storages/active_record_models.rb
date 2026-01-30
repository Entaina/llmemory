# frozen_string_literal: true

module Llmemory
  module LongTerm
    module GraphBased
      module Storages
        class LlmemoryGraphNode < ::ActiveRecord::Base
          self.table_name = "llmemory_graph_nodes"
          self.primary_key = "id"
          has_many :out_edges, class_name: "Llmemory::LongTerm::GraphBased::Storages::LlmemoryGraphEdge", foreign_key: :subject_id
          has_many :in_edges, class_name: "Llmemory::LongTerm::GraphBased::Storages::LlmemoryGraphEdge", foreign_key: :object_id
        end

        class LlmemoryGraphEdge < ::ActiveRecord::Base
          self.table_name = "llmemory_graph_edges"
          self.primary_key = "id"
          belongs_to :subject_node, class_name: "Llmemory::LongTerm::GraphBased::Storages::LlmemoryGraphNode", foreign_key: :subject_id, optional: true
          belongs_to :object_node, class_name: "Llmemory::LongTerm::GraphBased::Storages::LlmemoryGraphNode", foreign_key: :object_id, optional: true
        end
      end
    end
  end
end
