# frozen_string_literal: true

require "securerandom"
require_relative "base"
require_relative "../node"
require_relative "../edge"

module Llmemory
  module LongTerm
    module GraphBased
      module Storages
        class MemoryStorage < Base
          def initialize
            @nodes = Hash.new { |h, k| h[k] = {} }
            @edges = Hash.new { |h, k| h[k] = [] }
            @node_id_seq = 0
            @edge_id_seq = 0
          end

          def save_node(user_id, node)
            n = node.is_a?(Node) ? node : Node.from_h(node.to_h)
            unless n.id
              @node_id_seq += 1
              n = Node.new(
                id: "node_#{@node_id_seq}",
                user_id: user_id,
                entity_type: n.entity_type,
                name: n.name,
                properties: n.properties || {},
                created_at: n.created_at || Time.now,
                updated_at: Time.now
              )
            end
            @nodes[user_id][n.id] = n
            n.id
          end

          def find_node_by_id(user_id, id)
            @nodes[user_id][id]
          end

          def find_node_by_name(user_id, entity_type, name)
            @nodes[user_id].values.find { |n| n.entity_type == entity_type.to_s && n.name.to_s == name.to_s }
          end

          def list_nodes(user_id, entity_type: nil, limit: nil)
            list = @nodes[user_id].values
            list = list.select { |n| n.entity_type.to_s == entity_type.to_s } if entity_type
            limit ? list.take(limit) : list
          end

          def save_edge(user_id, edge)
            e = edge.is_a?(Edge) ? edge : Edge.from_h(edge.to_h)
            unless e.id
              @edge_id_seq += 1
              e = Edge.new(
                id: "edge_#{@edge_id_seq}",
                user_id: user_id,
                subject_id: e.subject_id,
                predicate: e.predicate,
                target_id: e.target_id,
                properties: e.properties || {},
                created_at: e.created_at || Time.now,
                archived_at: nil
              )
            end
            idx = @edges[user_id].find_index { |x| x.id == e.id }
            if idx
              @edges[user_id][idx] = e
            else
              @edges[user_id] << e
            end
            e.id
          end

          def find_edges(user_id, subject_id: nil, predicate: nil, object_id: nil, include_archived: false)
            list = @edges[user_id].select do |e|
              next false unless include_archived || !e.archived?
              next false if subject_id && e.subject_id != subject_id
              next false if predicate && e.predicate != predicate.to_s
              next false if object_id && e.target_id != object_id
              true
            end
            list
          end

          def archive_edge(user_id, edge_id, archived_at: nil)
            t = archived_at || Time.now
            e = @edges[user_id].find { |x| x.id == edge_id }
            return false unless e
            @edges[user_id].delete(e)
            @edges[user_id] << Edge.new(
              id: e.id,
              user_id: e.user_id,
              subject_id: e.subject_id,
              predicate: e.predicate,
              target_id: e.target_id,
              properties: e.properties,
              created_at: e.created_at,
              archived_at: t
            )
            true
          end

          def list_users
            (@nodes.keys + @edges.keys).uniq
          end

          def list_edges(user_id, subject_id: nil, predicate: nil, limit: nil)
            list = find_edges(user_id, subject_id: subject_id, predicate: predicate, object_id: nil, include_archived: false)
            limit ? list.take(limit) : list
          end

          def count_nodes(user_id)
            @nodes[user_id].size
          end

          def count_edges(user_id)
            @edges[user_id].count { |e| !e.archived? }
          end
        end
      end
    end
  end
end
