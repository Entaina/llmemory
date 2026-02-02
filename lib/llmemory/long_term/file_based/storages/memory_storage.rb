# frozen_string_literal: true

require_relative "base"

module Llmemory
  module LongTerm
    module FileBased
      module Storages
        class MemoryStorage < Base
          def initialize
            @resources = Hash.new { |h, k| h[k] = [] }
            @items = Hash.new { |h, k| h[k] = [] }
            @categories = Hash.new { |h, k| h[k] = {} }
            @resource_id_seq = 0
            @item_id_seq = 0
          end

          def save_resource(user_id, text)
            @resource_id_seq += 1
            id = "res_#{@resource_id_seq}"
            @resources[user_id] << { id: id, text: text, created_at: Time.now }
            id
          end

          def save_item(user_id, category:, content:, source_resource_id:)
            @item_id_seq += 1
            id = "item_#{@item_id_seq}"
            @items[user_id] << {
              id: id,
              category: category,
              content: content,
              source_resource_id: source_resource_id,
              created_at: Time.now
            }
            id
          end

          def load_category(user_id, category_name)
            @categories[user_id][category_name].to_s
          end

          def save_category(user_id, category_name, content)
            @categories[user_id][category_name] = content
            true
          end

          def list_categories(user_id)
            @categories[user_id].keys
          end

          def search_items(user_id, query)
            query_lower = query.downcase
            @items[user_id].select { |i| i[:content].to_s.downcase.include?(query_lower) }
          end

          def search_resources(user_id, query)
            query_lower = query.downcase
            @resources[user_id].select { |r| r[:text].to_s.downcase.include?(query_lower) }
          end

          def get_resources_since(user_id, hours:)
            cutoff = Time.now - (hours * 3600)
            @resources[user_id].select { |r| r[:created_at] >= cutoff }
          end

          def get_items_older_than(user_id, days:)
            cutoff = Time.now - (days * 86400)
            @items[user_id].select { |i| i[:created_at] < cutoff }
          end

          def get_all_items(user_id)
            @items[user_id].dup
          end

          def get_all_resources(user_id)
            @resources[user_id].dup
          end

          def get_items_since(user_id, hours:)
            cutoff = Time.now - (hours * 3600)
            @items[user_id].select { |i| i[:created_at] >= cutoff }
          end

          def replace_items(user_id, ids_to_remove, merged_item)
            @items[user_id].reject! { |i| ids_to_remove.include?(i[:id]) }
            @items[user_id] << merged_item.merge(created_at: Time.now)
          end

          def archive_items(user_id, item_ids)
            @items[user_id].reject! { |i| item_ids.include?(i[:id]) }
          end

          def archive_resources(user_id, resource_ids)
            @resources[user_id].reject! { |r| resource_ids.include?(r[:id]) }
          end

          def list_users
            (@resources.keys + @items.keys + @categories.keys).uniq
          end

          def list_resources(user_id:, limit: nil)
            list = @resources[user_id].dup
            limit ? list.take(limit) : list
          end

          def list_items(user_id:, category: nil, limit: nil)
            list = if category
              @items[user_id].select { |i| i[:category].to_s == category.to_s }
            else
              @items[user_id].dup
            end
            list = list.take(limit) if limit
            list
          end

          def count_items(user_id:)
            @items[user_id].size
          end

          def get_items_around(user_id, reference, before: 5, after: 5)
            items = @items[user_id].sort_by { |i| i[:created_at] }
            find_around(items, reference, :id, before, after)
          end

          def get_resources_around(user_id, reference, before: 5, after: 5)
            resources = @resources[user_id].sort_by { |r| r[:created_at] }
            find_around(resources, reference, :id, before, after)
          end

          private

          def find_around(items, reference, id_key, before, after)
            return { before: [], target: nil, after: [] } if items.empty?

            idx = if reference.is_a?(String) && reference.match?(/^\d{4}-/)
              # ISO timestamp - find closest item at or after this time
              target_time = Time.parse(reference)
              items.index { |i| i[:created_at] >= target_time } || items.size
            else
              # Item ID
              items.index { |i| i[id_key] == reference }
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
