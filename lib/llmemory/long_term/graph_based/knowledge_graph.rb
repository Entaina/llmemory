# frozen_string_literal: true

require_relative "node"
require_relative "edge"
require_relative "storages/base"
require_relative "storages/memory_storage"

module Llmemory
  module LongTerm
    module GraphBased
      class KnowledgeGraph
        def initialize(user_id:, storage: nil)
          @user_id = user_id
          @storage = storage || Storages::MemoryStorage.new
        end

        def add_node(entity_type:, name:, properties: {})
          existing = @storage.find_node_by_name(@user_id, entity_type, name)
          return existing.id if existing
          node = Node.new(
            id: nil,
            user_id: @user_id,
            entity_type: entity_type.to_s,
            name: name.to_s,
            properties: properties,
            created_at: Time.now,
            updated_at: Time.now
          )
          @storage.save_node(@user_id, node)
        end

        def find_node(name: nil, id: nil)
          if id
            @storage.find_node_by_id(@user_id, id)
          elsif name
            list_nodes.find { |n| n.name.to_s == name.to_s }
          end
        end

        def find_node_by_id(id)
          @storage.find_node_by_id(@user_id, id)
        end

        def add_edge(subject:, predicate:, object:, properties: {})
          subject_id = subject.is_a?(Node) ? subject.id : subject.to_s
          object_id = object.is_a?(Node) ? object.id : object.to_s
          edge = Edge.new(
            id: nil,
            user_id: @user_id,
            subject_id: subject_id,
            predicate: predicate.to_s,
            object_id: object_id,
            properties: properties,
            created_at: Time.now,
            archived_at: nil
          )
          @storage.save_edge(@user_id, edge)
        end

        def find_edges(subject: nil, predicate: nil, object: nil, include_archived: false)
          subject_id = subject.is_a?(Node) ? subject.id : subject
          object_id = object.is_a?(Node) ? object.id : object
          @storage.find_edges(
            @user_id,
            subject_id: subject_id,
            predicate: predicate&.to_s,
            object_id: object_id,
            include_archived: include_archived
          )
        end

        def traverse(start_node:, depth: 2)
          start_id = start_node.is_a?(Node) ? start_node.id : start_node.to_s
          visited = {}
          queue = [[start_id, 0]]
          result_nodes = []
          result_edges = []

          while queue.any?
            node_id, d = queue.shift
            next if d > depth
            next if visited[node_id]
            visited[node_id] = true
            node = @storage.find_node_by_id(@user_id, node_id)
            result_nodes << node if node

            edges = @storage.find_edges(@user_id, subject_id: node_id, include_archived: false)
            edges.each do |e|
              result_edges << e
              queue << [e.object_id, d + 1] unless visited[e.object_id]
            end
            edges_out = @storage.find_edges(@user_id, object_id: node_id, include_archived: false)
            edges_out.each do |e|
              result_edges << e
              queue << [e.subject_id, d + 1] unless visited[e.subject_id]
            end
          end

          { nodes: result_nodes.uniq, edges: result_edges.uniq }
        end

        def archive_edge(edge_id, reason: nil)
          @storage.archive_edge(@user_id, edge_id, archived_at: Time.now)
        end

        def list_nodes
          @storage.list_nodes(@user_id)
        end

        attr_reader :storage, :user_id
      end
    end
  end
end
