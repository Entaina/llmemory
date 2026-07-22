# frozen_string_literal: true

module Llmemory
  module LongTerm
    module FileBased
      module Storages
        class Base
          def save_resource(user_id, text)
            raise NotImplementedError, "#{self.class}#save_resource must be implemented"
          end

          def save_item(user_id, category:, content:, source_resource_id:, importance: 0.7, provenance: nil)
            raise NotImplementedError, "#{self.class}#save_item must be implemented"
          end

          def load_category(user_id, category_name)
            raise NotImplementedError, "#{self.class}#load_category must be implemented"
          end

          def save_category(user_id, category_name, content)
            raise NotImplementedError, "#{self.class}#save_category must be implemented"
          end

          def list_categories(user_id)
            raise NotImplementedError, "#{self.class}#list_categories must be implemented"
          end

          def search_items(user_id, query)
            raise NotImplementedError, "#{self.class}#search_items must be implemented"
          end

          def search_resources(user_id, query)
            raise NotImplementedError, "#{self.class}#search_resources must be implemented"
          end

          def get_resources_since(user_id, hours:)
            raise NotImplementedError, "#{self.class}#get_resources_since must be implemented"
          end

          def get_items_older_than(user_id, days:)
            raise NotImplementedError, "#{self.class}#get_items_older_than must be implemented"
          end

          def get_all_items(user_id)
            raise NotImplementedError, "#{self.class}#get_all_items must be implemented"
          end

          def get_all_resources(user_id)
            raise NotImplementedError, "#{self.class}#get_all_resources must be implemented"
          end

          def get_items_since(user_id, hours:)
            raise NotImplementedError, "#{self.class}#get_items_since must be implemented"
          end

          def replace_items(user_id, ids_to_remove, merged_item)
            raise NotImplementedError, "#{self.class}#replace_items must be implemented"
          end

          def archive_items(user_id, item_ids)
            raise NotImplementedError, "#{self.class}#archive_items must be implemented"
          end

          def archive_resources(user_id, resource_ids)
            raise NotImplementedError, "#{self.class}#archive_resources must be implemented"
          end

          def list_users
            raise NotImplementedError, "#{self.class}#list_users must be implemented"
          end

          def list_resources(user_id:, limit: nil, offset: nil)
            raise NotImplementedError, "#{self.class}#list_resources must be implemented"
          end

          def list_items(user_id:, category: nil, limit: nil, offset: nil)
            raise NotImplementedError, "#{self.class}#list_items must be implemented"
          end

          def count_items(user_id:)
            raise NotImplementedError, "#{self.class}#count_items must be implemented"
          end

          def get_items_around(user_id, reference, before: 5, after: 5)
            raise NotImplementedError, "#{self.class}#get_items_around must be implemented"
          end

          def get_resources_around(user_id, reference, before: 5, after: 5)
            raise NotImplementedError, "#{self.class}#get_resources_around must be implemented"
          end

          protected

          def find_around(items, reference, before, after, id_key: :id)
            return { before: [], target: nil, after: [] } if items.empty?

            idx = if reference.is_a?(String) && reference.match?(/^\d{4}-/)
              target_time = Time.parse(reference)
              items.index { |i| (i[:created_at] || i["created_at"]) >= target_time } || items.size
            else
              items.index { |i| (i[id_key] || i[id_key.to_s]) == reference }
            end

            return { before: [], target: nil, after: [] } unless idx

            start_idx = [idx - before, 0].max
            end_idx = [idx + after, items.size - 1].min

            {
              before: items[start_idx...idx] || [],
              target: items[idx],
              after: items[(idx + 1)..end_idx] || []
            }
          end
        end
      end
    end
  end
end
