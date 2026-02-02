# frozen_string_literal: true

require_relative "base"
require_relative "active_record_models"
require_relative "../node"
require_relative "../edge"

module Llmemory
  module LongTerm
    module GraphBased
      module Storages
        class ActiveRecordStorage < Base
          def initialize
            self.class.load_models!
          end

          def self.load_models!
            return if @models_loaded
            require "active_record"
            require_relative "active_record_models"
            @models_loaded = true
          end

          def save_node(user_id, node)
            n = node.is_a?(Node) ? node : Node.from_h(node.to_h)
            rec = if n.id
              LlmemoryGraphNode.find_by(user_id: user_id, id: n.id)
            else
              LlmemoryGraphNode.find_by(user_id: user_id, entity_type: n.entity_type, name: n.name)
            end
            if rec
              rec.update!(properties: n.properties || {}, updated_at: Time.current)
              rec.id
            else
              rec = LlmemoryGraphNode.create!(
                user_id: user_id,
                entity_type: n.entity_type.to_s,
                name: n.name.to_s,
                properties: n.properties || {}
              )
              rec.id
            end
          end

          def find_node_by_id(user_id, id)
            rec = LlmemoryGraphNode.find_by(user_id: user_id, id: id)
            record_to_node(rec) if rec
          end

          def find_node_by_name(user_id, entity_type, name)
            rec = LlmemoryGraphNode.find_by(user_id: user_id, entity_type: entity_type.to_s, name: name.to_s)
            record_to_node(rec) if rec
          end

          def list_nodes(user_id, entity_type: nil, limit: nil)
            scope = LlmemoryGraphNode.where(user_id: user_id)
            scope = scope.where(entity_type: entity_type) if entity_type
            scope = scope.limit(limit) if limit && limit.to_i.positive?
            scope.map { |r| record_to_node(r) }
          end

          def save_edge(user_id, edge)
            e = edge.is_a?(Edge) ? edge : Edge.from_h(edge.to_h)
            rec = if e.id && e.id.is_a?(Integer)
              LlmemoryGraphEdge.find_by(user_id: user_id, id: e.id)
            else
              nil
            end
            if rec
              rec.update!(
                subject_id: e.subject_id,
                predicate: e.predicate,
                object_id: e.target_id,
                properties: e.properties || {}
              )
              rec.id
            else
              rec = LlmemoryGraphEdge.create!(
                user_id: user_id,
                subject_id: e.subject_id,
                predicate: e.predicate,
                object_id: e.target_id,
                properties: e.properties || {}
              )
              rec.id
            end
          end

          def find_edges(user_id, subject_id: nil, predicate: nil, object_id: nil, include_archived: false)
            scope = LlmemoryGraphEdge.where(user_id: user_id)
            scope = scope.where(archived_at: nil) unless include_archived
            scope = scope.where(subject_id: subject_id) if subject_id
            scope = scope.where(predicate: predicate) if predicate
            scope = scope.where(object_id: object_id) if object_id
            scope.map { |r| record_to_edge(r) }
          end

          def archive_edge(user_id, edge_id, archived_at: nil)
            rec = LlmemoryGraphEdge.find_by(user_id: user_id, id: edge_id)
            return false unless rec
            rec.update!(archived_at: archived_at || Time.current)
            true
          end

          def list_users
            (LlmemoryGraphNode.distinct.pluck(:user_id) + LlmemoryGraphEdge.distinct.pluck(:user_id)).uniq
          end

          def list_edges(user_id, subject_id: nil, predicate: nil, limit: nil)
            scope = LlmemoryGraphEdge.where(user_id: user_id, archived_at: nil)
            scope = scope.where(subject_id: subject_id) if subject_id
            scope = scope.where(predicate: predicate) if predicate
            scope = scope.order(created_at: :desc) if limit && limit.to_i.positive?
            scope = scope.limit(limit) if limit && limit.to_i.positive?
            scope.map { |r| record_to_edge(r) }
          end

          def count_nodes(user_id)
            LlmemoryGraphNode.where(user_id: user_id).count
          end

          def count_edges(user_id)
            LlmemoryGraphEdge.where(user_id: user_id, archived_at: nil).count
          end

          def get_edges_around(user_id, reference, before: 5, after: 5)
            edges = LlmemoryGraphEdge.where(user_id: user_id, archived_at: nil)
              .order(:created_at)
              .map { |r| record_to_edge(r) }

            return { before: [], target: nil, after: [] } if edges.empty?

            idx = if reference.is_a?(String) && reference.match?(/^\d{4}-/)
              target_time = Time.parse(reference)
              edges.index { |e| e.created_at >= target_time } || edges.size
            else
              edges.index { |e| e.id == reference || e.id.to_s == reference.to_s }
            end

            return { before: [], target: nil, after: [] } unless idx

            start_idx = [idx - before, 0].max
            end_idx = [idx + after, edges.size - 1].min

            {
              before: edges[start_idx...idx] || [],
              target: edges[idx],
              after: edges[(idx + 1)..end_idx] || []
            }
          end

          private

          def record_to_node(r)
            Node.new(
              id: r.id,
              user_id: r.user_id,
              entity_type: r.entity_type,
              name: r.name,
              properties: r.properties || {},
              created_at: r.created_at,
              updated_at: r.updated_at
            )
          end

          def record_to_edge(r)
            Edge.new(
              id: r.id,
              user_id: r.user_id,
              subject_id: r.subject_id,
              predicate: r.predicate,
              target_id: r.object_id,
              properties: r.properties || {},
              created_at: r.created_at,
              archived_at: r.archived_at
            )
          end
        end
      end
    end
  end
end
