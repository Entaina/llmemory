# frozen_string_literal: true

require "securerandom"
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
              id = n.id || "node_#{SecureRandom.hex(8)}"
              LlmemoryGraphNode.create!(
                id: id,
                user_id: user_id,
                entity_type: n.entity_type.to_s,
                name: n.name.to_s,
                properties: n.properties || {}
              )
              id
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
            id = e.id || "edge_#{SecureRandom.hex(8)}"
            rec = LlmemoryGraphEdge.find_by(user_id: user_id, id: id)
            if rec
              rec.update!(
                subject_id: e.subject_id,
                predicate: e.predicate,
                object_id: e.object_id,
                properties: e.properties || {}
              )
            else
              LlmemoryGraphEdge.create!(
                id: id,
                user_id: user_id,
                subject_id: e.subject_id,
                predicate: e.predicate,
                object_id: e.object_id,
                properties: e.properties || {}
              )
            end
            id
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
            scope = scope.limit(limit) if limit && limit.to_i.positive?
            scope.map { |r| record_to_edge(r) }
          end

          def count_nodes(user_id)
            LlmemoryGraphNode.where(user_id: user_id).count
          end

          def count_edges(user_id)
            LlmemoryGraphEdge.where(user_id: user_id, archived_at: nil).count
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
              object_id: r.object_id,
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
