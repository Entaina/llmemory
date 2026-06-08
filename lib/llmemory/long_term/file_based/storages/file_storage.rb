# frozen_string_literal: true

require "fileutils"
require "json"
require_relative "base"

module Llmemory
  module LongTerm
    module FileBased
      module Storages
        class FileStorage < Base
          def initialize(base_path: nil)
            @base_path = base_path || Llmemory.configuration.long_term_storage_path || "./llmemory_data"
            @base_path = File.expand_path(@base_path)
          end

          def save_resource(user_id, text)
            ensure_user_dir(user_id)
            seq = next_seq(user_id, "resource_id_seq")
            id = "res_#{seq}"
            path = resource_path(user_id, id)
            data = { text: text, created_at: Time.now.iso8601 }
            File.write(path, JSON.generate(data))
            id
          end

          def save_item(user_id, category:, content:, source_resource_id:, importance: 0.7, provenance: nil)
            ensure_user_dir(user_id)
            seq = next_seq(user_id, "item_id_seq")
            id = "item_#{seq}"
            path = item_path(user_id, id)
            data = {
              id: id,
              category: category,
              content: content,
              source_resource_id: source_resource_id,
              importance: importance,
              provenance: provenance,
              created_at: Time.now.iso8601
            }
            File.write(path, JSON.generate(data))
            id
          end

          def load_category(user_id, category_name)
            path = category_path(user_id, category_name)
            return "" unless File.file?(path)
            File.read(path)
          end

          def save_category(user_id, category_name, content)
            ensure_user_dir(user_id, "categories")
            path = category_path(user_id, category_name)
            File.write(path, content)
            true
          end

          def list_categories(user_id)
            dir = user_path(user_id, "categories")
            return [] unless Dir.exist?(dir)
            Dir.children(dir).select { |f| f.end_with?(".md") }.map { |f| File.basename(f, ".md") }
          end

          def search_items(user_id, query)
            get_all_items(user_id).select { |i| Llmemory::Tokenizer.matches?(i[:content] || i["content"], query) }
          end

          def search_resources(user_id, query)
            get_all_resources(user_id).select { |r| Llmemory::Tokenizer.matches?(r[:text] || r["text"], query) }
          end

          def get_resources_since(user_id, hours:)
            cutoff = Time.now - (hours * 3600)
            get_all_resources(user_id).select { |r| parse_time(r[:created_at] || r["created_at"]) >= cutoff }
          end

          def get_items_older_than(user_id, days:)
            cutoff = Time.now - (days * 86400)
            get_all_items(user_id).select { |i| parse_time(i[:created_at] || i["created_at"]) < cutoff }
          end

          def get_all_items(user_id)
            dir = user_path(user_id, "items")
            return [] unless Dir.exist?(dir)
            Dir.children(dir).select { |f| f.end_with?(".json") }.map do |f|
              data = JSON.parse(File.read(File.join(dir, f)), symbolize_names: true)
              data[:created_at] = parse_time(data[:created_at])
              data
            end.sort_by { |i| i[:created_at] }
          end

          def get_all_resources(user_id)
            dir = user_path(user_id, "resources")
            return [] unless Dir.exist?(dir)
            Dir.children(dir).select { |f| f.end_with?(".json") }.map do |f|
              data = JSON.parse(File.read(File.join(dir, f)), symbolize_names: true)
              id = File.basename(f, ".json")
              data[:id] = id
              data[:created_at] = parse_time(data[:created_at])
              data
            end.sort_by { |r| r[:created_at] }
          end

          def get_items_since(user_id, hours:)
            cutoff = Time.now - (hours * 3600)
            get_all_items(user_id).select { |i| parse_time(i[:created_at]) >= cutoff }
          end

          def replace_items(user_id, ids_to_remove, merged_item)
            ids_to_remove.each { |id| File.delete(item_path(user_id, id)) if File.file?(item_path(user_id, id)) }
            merged_item = merged_item.merge(created_at: Time.now) unless merged_item.key?(:created_at)
            seq = next_seq(user_id, "item_id_seq")
            id = "item_#{seq}"
            path = item_path(user_id, id)
            data = merged_item.merge(id: id).transform_values { |v| v.respond_to?(:iso8601) ? v.iso8601 : v }
            File.write(path, JSON.generate(data))
          end

          def archive_items(user_id, item_ids)
            item_ids.each { |id| File.delete(item_path(user_id, id)) if File.file?(item_path(user_id, id)) }
          end

          def archive_resources(user_id, resource_ids)
            resource_ids.each { |id| File.delete(resource_path(user_id, id)) if File.file?(resource_path(user_id, id)) }
          end

          def save_daily_log_entry(user_id, date, content)
            ensure_user_dir(user_id, "memory")
            path = daily_log_path(user_id, date)
            existing = File.file?(path) ? File.read(path) : ""
            entry = "#{Time.now.strftime('%H:%M')} #{content}\n"
            File.write(path, existing + entry)
            true
          end

          def load_daily_logs(user_id, from_date:, to_date:)
            from_date = Date.parse(from_date.to_s) if from_date.is_a?(String)
            to_date = Date.parse(to_date.to_s) if to_date.is_a?(String)
            dir = user_path(user_id, "memory")
            return [] unless Dir.exist?(dir)

            (from_date..to_date).filter_map do |d|
              path = daily_log_path(user_id, d)
              next unless File.file?(path)

              { date: d, content: File.read(path) }
            end
          end

          def list_users
            return [] unless Dir.exist?(@base_path)
            Dir.children(@base_path).select { |e| File.directory?(File.join(@base_path, e)) && !e.start_with?(".") }
          end

          def list_resources(user_id:, limit: nil, offset: nil)
            list = get_all_resources(user_id)
            list = list.drop(offset.to_i) if offset && offset.to_i.positive?
            limit ? list.take(limit) : list
          end

          def list_items(user_id:, category: nil, limit: nil, offset: nil)
            list = get_all_items(user_id)
            list = list.select { |i| (i[:category] || i["category"]).to_s == category.to_s } if category
            list = list.drop(offset.to_i) if offset && offset.to_i.positive?
            list = list.take(limit) if limit
            list
          end

          def count_items(user_id:)
            get_all_items(user_id).size
          end

          private

          def user_path(user_id, *parts)
            safe = user_id.to_s.gsub(%r{[^\w\-.]}, "_")
            File.join(@base_path, safe, *parts)
          end

          def resource_path(user_id, id)
            ensure_user_dir(user_id, "resources")
            File.join(user_path(user_id, "resources"), "#{id}.json")
          end

          def item_path(user_id, id)
            ensure_user_dir(user_id, "items")
            File.join(user_path(user_id, "items"), "#{id}.json")
          end

          def daily_log_path(user_id, date)
            date_str = date.respond_to?(:strftime) ? date.strftime("%Y-%m-%d") : date.to_s
            File.join(user_path(user_id, "memory"), "#{date_str}.md")
          end

          def category_path(user_id, category_name)
            safe = category_name.to_s.gsub(%r{[^\w\-.]}, "_")
            File.join(user_path(user_id, "categories"), "#{safe}.md")
          end

          def ensure_user_dir(user_id, *subdirs)
            dir = user_path(user_id, *subdirs)
            FileUtils.mkdir_p(dir)
          end

          def meta_path(user_id)
            File.join(user_path(user_id), "meta.json")
          end

          def next_seq(user_id, key)
            ensure_user_dir(user_id)
            path = meta_path(user_id)
            meta = if File.file?(path)
              JSON.parse(File.read(path))
            else
              {}
            end
            meta[key] = (meta[key] || 0) + 1
            File.write(path, JSON.generate(meta))
            meta[key]
          end

          def parse_time(val)
            return val if val.is_a?(Time)
            return Time.parse(val.to_s) if val
            Time.now
          end
        end
      end
    end
  end
end
