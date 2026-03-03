# frozen_string_literal: true

require "securerandom"
require_relative "base"

module Llmemory
  module LongTerm
    module FileBased
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

          def save_resource(user_id, text)
            id = "res_#{SecureRandom.hex(8)}"
            LlmemoryResource.create!(
              id: id,
              user_id: user_id,
              text: text,
              created_at: Time.current
            )
            id
          end

          def save_item(user_id, category:, content:, source_resource_id:, importance: 0.7)
            id = "item_#{SecureRandom.hex(8)}"
            attrs = {
              id: id,
              user_id: user_id,
              category: category,
              content: content,
              source_resource_id: source_resource_id,
              created_at: Time.current
            }
            attrs[:importance] = importance if LlmemoryItem.column_names.include?("importance")
            LlmemoryItem.create!(attrs)
            id
          end

          def load_category(user_id, category_name)
            rec = LlmemoryCategory.find_by(user_id: user_id, category_name: category_name)
            rec ? rec.content.to_s : ""
          end

          def save_category(user_id, category_name, content)
            rec = LlmemoryCategory.find_or_initialize_by(user_id: user_id, category_name: category_name)
            rec.content = content
            rec.updated_at = Time.current
            rec.save!
            true
          end

          def list_categories(user_id)
            LlmemoryCategory.where(user_id: user_id).pluck(:category_name)
          end

          def search_items(user_id, query)
            q = "%#{sanitize_like(query)}%"
            LlmemoryItem.where(user_id: user_id).where("LOWER(content) LIKE LOWER(?)", q).map { |r| row_to_item(r) }
          end

          def search_resources(user_id, query)
            q = "%#{sanitize_like(query)}%"
            LlmemoryResource.where(user_id: user_id).where("LOWER(text) LIKE LOWER(?)", q).map { |r| row_to_resource(r) }
          end

          def get_resources_since(user_id, hours:)
            cutoff = hours.hours.ago
            LlmemoryResource.where(user_id: user_id).where("created_at >= ?", cutoff).order(:created_at).map { |r| row_to_resource(r) }
          end

          def get_items_older_than(user_id, days:)
            cutoff = days.days.ago
            LlmemoryItem.where(user_id: user_id).where("created_at < ?", cutoff).order(:created_at).map { |r| row_to_item(r) }
          end

          def get_all_items(user_id)
            LlmemoryItem.where(user_id: user_id).order(:created_at).map { |r| row_to_item(r) }
          end

          def get_all_resources(user_id)
            LlmemoryResource.where(user_id: user_id).order(:created_at).map { |r| row_to_resource(r) }
          end

          def get_items_since(user_id, hours:)
            cutoff = hours.hours.ago
            LlmemoryItem.where(user_id: user_id).where("created_at >= ?", cutoff).order(:created_at).map { |r| row_to_item(r) }
          end

          def replace_items(user_id, ids_to_remove, merged_item)
            LlmemoryItem.where(user_id: user_id, id: ids_to_remove).destroy_all
            created_at = merged_item[:created_at] || Time.current
            attrs = {
              id: "item_#{SecureRandom.hex(8)}",
              user_id: user_id,
              category: merged_item[:category],
              content: merged_item[:content],
              source_resource_id: merged_item[:source_resource_id],
              created_at: created_at
            }
            attrs[:importance] = merged_item[:importance] if LlmemoryItem.column_names.include?("importance") && merged_item[:importance]
            LlmemoryItem.create!(attrs)
          end

          def archive_items(user_id, item_ids)
            LlmemoryItem.where(user_id: user_id, id: item_ids).destroy_all
          end

          def archive_resources(user_id, resource_ids)
            LlmemoryResource.where(user_id: user_id, id: resource_ids).destroy_all
          end

          def list_users
            (LlmemoryResource.distinct.pluck(:user_id) +
             LlmemoryItem.distinct.pluck(:user_id) +
             LlmemoryCategory.distinct.pluck(:user_id)).uniq
          end

          def list_resources(user_id:, limit: nil)
            scope = LlmemoryResource.where(user_id: user_id).order(:created_at)
            scope = scope.limit(limit) if limit && limit.to_i.positive?
            scope.map { |r| row_to_resource(r) }
          end

          def list_items(user_id:, category: nil, limit: nil)
            scope = LlmemoryItem.where(user_id: user_id)
            scope = scope.where(category: category) if category
            scope = scope.order(:created_at)
            scope = scope.limit(limit) if limit && limit.to_i.positive?
            scope.map { |r| row_to_item(r) }
          end

          def count_items(user_id:)
            LlmemoryItem.where(user_id: user_id).count
          end

          def get_items_around(user_id, reference, before: 5, after: 5)
            items = get_all_items(user_id)
            find_around(items, reference, before, after)
          end

          def get_resources_around(user_id, reference, before: 5, after: 5)
            resources = get_all_resources(user_id)
            find_around(resources, reference, before, after)
          end

          private

          def find_around(items, reference, before, after)
            return { before: [], target: nil, after: [] } if items.empty?

            idx = if reference.is_a?(String) && reference.match?(/^\d{4}-/)
              target_time = Time.parse(reference)
              items.index { |i| i[:created_at] >= target_time } || items.size
            else
              items.index { |i| i[:id] == reference }
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

          def sanitize_like(str)
            (str || "").to_s.gsub(/[%_\\]/) { |c| "\\#{c}" }
          end

          def row_to_item(r)
            h = {
              id: r.id,
              category: r.category,
              content: r.content,
              source_resource_id: r.source_resource_id,
              created_at: r.created_at
            }
            h[:importance] = r.respond_to?(:importance) ? (r.importance || 0.7).to_f : 0.7
            h
          end

          def row_to_resource(r)
            {
              id: r.id,
              text: r.text,
              created_at: r.created_at
            }
          end
        end
      end
    end
  end
end
