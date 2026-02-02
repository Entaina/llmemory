# frozen_string_literal: true

module Llmemory
  module LongTerm
    module GraphBased
      module Storages
        class Base
          def save_node(user_id, node)
            raise NotImplementedError, "#{self.class}#save_node must be implemented"
          end

          def find_node_by_id(user_id, id)
            raise NotImplementedError, "#{self.class}#find_node_by_id must be implemented"
          end

          def find_node_by_name(user_id, entity_type, name)
            raise NotImplementedError, "#{self.class}#find_node_by_name must be implemented"
          end

          def list_nodes(user_id, entity_type: nil, limit: nil)
            raise NotImplementedError, "#{self.class}#list_nodes must be implemented"
          end

          def save_edge(user_id, edge)
            raise NotImplementedError, "#{self.class}#save_edge must be implemented"
          end

          def find_edges(user_id, subject_id: nil, predicate: nil, object_id: nil, include_archived: false)
            raise NotImplementedError, "#{self.class}#find_edges must be implemented"
          end

          def archive_edge(user_id, edge_id, archived_at: nil)
            raise NotImplementedError, "#{self.class}#archive_edge must be implemented"
          end

          def list_users
            raise NotImplementedError, "#{self.class}#list_users must be implemented"
          end

          def list_edges(user_id, subject_id: nil, predicate: nil, limit: nil)
            raise NotImplementedError, "#{self.class}#list_edges must be implemented"
          end

          def count_nodes(user_id)
            raise NotImplementedError, "#{self.class}#count_nodes must be implemented"
          end

          def count_edges(user_id)
            raise NotImplementedError, "#{self.class}#count_edges must be implemented"
          end
        end
      end
    end
  end
end
