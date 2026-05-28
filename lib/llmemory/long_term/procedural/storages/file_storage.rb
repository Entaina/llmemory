# frozen_string_literal: true

require "fileutils"
require "json"
require "time"
require_relative "base"

module Llmemory
  module LongTerm
    module Procedural
      module Storages
        class FileStorage < Base
          def initialize(base_path: nil)
            @base_path = base_path || Llmemory.configuration.long_term_storage_path || "./llmemory_data"
            @base_path = File.expand_path(@base_path)
          end

          def save_skill(user_id, skill)
            id = skill[:id] || skill["id"] || "skill_#{next_seq(user_id)}"
            data = stringify_for_json(skill).merge("id" => id, "user_id" => user_id)
            data["created_at"] ||= Time.now.iso8601(6)
            File.write(skill_path(user_id, id), JSON.generate(data))
            id
          end

          def get_skill(user_id, id)
            path = skill_path(user_id, id)
            return nil unless File.file?(path)
            load_skill(path)
          end

          def list_skills(user_id, limit: nil)
            sorted = all_skills(user_id).sort_by { |s| s[:created_at] }.reverse
            limit && limit.to_i.positive? ? sorted.first(limit.to_i) : sorted
          end

          def search_skills(user_id, query)
            return list_skills(user_id) if query.to_s.strip.empty?
            all_skills(user_id).select { |s| Llmemory::Tokenizer.matches?(skill_text(s), query) }
          end

          def find_skills_by_name(user_id, name)
            all_skills(user_id).select { |s| s[:name].to_s == name.to_s }
          end

          def record_outcome(user_id, skill_id, success:)
            skill = get_skill(user_id, skill_id)
            return nil unless skill
            key = success ? :success_count : :failure_count
            skill[key] = (skill[key] || 0).to_i + 1
            skill[:updated_at] = Time.now.iso8601(6)
            File.write(skill_path(user_id, skill_id), JSON.generate(stringify_for_json(skill)))
            skill
          end

          def count_skills(user_id)
            dir = user_path(user_id, "skills")
            return 0 unless Dir.exist?(dir)
            Dir.children(dir).count { |f| f.end_with?(".json") }
          end

          def delete_skills(user_id, ids)
            Array(ids).map(&:to_s).count do |id|
              path = skill_path(user_id, id)
              next false unless File.file?(path)
              File.delete(path)
              true
            end
          end

          def list_users
            return [] unless Dir.exist?(@base_path)
            Dir.children(@base_path).select { |d| Dir.exist?(File.join(@base_path, d, "skills")) }
          end

          private

          def all_skills(user_id)
            dir = user_path(user_id, "skills")
            return [] unless Dir.exist?(dir)
            Dir.children(dir).select { |f| f.end_with?(".json") }.map { |f| load_skill(File.join(dir, f)) }.compact
          end

          def load_skill(path)
            data = JSON.parse(File.read(path), symbolize_names: true)
            data[:created_at] = parse_time(data[:created_at])
            data[:updated_at] = parse_time(data[:updated_at]) if data[:updated_at]
            data
          rescue JSON::ParserError
            nil
          end

          def skill_text(skill)
            [skill[:name], skill[:description], skill[:body]].compact.join("\n")
          end

          def stringify_for_json(skill)
            JSON.parse(JSON.generate(skill))
          end

          def user_path(user_id, *parts)
            safe = user_id.to_s.gsub(%r{[^\w\-.]}, "_")
            File.join(@base_path, safe, *parts)
          end

          def skill_path(user_id, id)
            dir = user_path(user_id, "skills")
            FileUtils.mkdir_p(dir)
            File.join(dir, "#{id}.json")
          end

          def meta_path(user_id)
            FileUtils.mkdir_p(user_path(user_id))
            File.join(user_path(user_id), "meta.json")
          end

          def next_seq(user_id)
            path = meta_path(user_id)
            meta = File.file?(path) ? JSON.parse(File.read(path)) : {}
            meta["skill_id_seq"] = (meta["skill_id_seq"] || 0) + 1
            File.write(path, JSON.generate(meta))
            meta["skill_id_seq"]
          end

          def parse_time(val)
            return val if val.is_a?(Time)
            Time.parse(val.to_s)
          rescue ArgumentError
            Time.now
          end
        end
      end
    end
  end
end
