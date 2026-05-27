# frozen_string_literal: true

require_relative "base"

module Llmemory
  module LongTerm
    module Procedural
      module Storages
        class MemoryStorage < Base
          def initialize
            @skills = Hash.new { |h, k| h[k] = [] }
            @seq = 0
          end

          def save_skill(user_id, skill)
            @seq += 1
            id = skill[:id] || skill["id"] || "skill_#{@seq}"
            record = symbolize(skill).merge(id: id, user_id: user_id)
            record[:created_at] ||= Time.now
            @skills[user_id] << record
            id
          end

          def get_skill(user_id, id)
            @skills[user_id].find { |s| s[:id] == id }
          end

          def list_skills(user_id, limit: nil)
            sorted = @skills[user_id].sort_by { |s| s[:created_at] }.reverse
            limit && limit.to_i.positive? ? sorted.first(limit.to_i) : sorted
          end

          def search_skills(user_id, query)
            q = query.to_s.downcase
            return list_skills(user_id) if q.strip.empty?
            @skills[user_id].select { |s| skill_text(s).downcase.include?(q) }
          end

          def find_skills_by_name(user_id, name)
            @skills[user_id].select { |s| s[:name].to_s == name.to_s }
          end

          def record_outcome(user_id, skill_id, success:)
            skill = get_skill(user_id, skill_id)
            return nil unless skill
            key = success ? :success_count : :failure_count
            skill[key] = (skill[key] || 0).to_i + 1
            skill[:updated_at] = Time.now
            skill
          end

          def count_skills(user_id)
            @skills[user_id].size
          end

          def delete_skills(user_id, ids)
            ids = Array(ids).map(&:to_s)
            before = @skills[user_id].size
            @skills[user_id].reject! { |s| ids.include?(s[:id].to_s) }
            before - @skills[user_id].size
          end

          def list_users
            @skills.keys
          end

          private

          def symbolize(hash)
            hash.each_with_object({}) { |(k, v), acc| acc[k.to_sym] = v }
          end

          def skill_text(skill)
            [skill[:name], skill[:description], skill[:body]].compact.join("\n")
          end
        end
      end
    end
  end
end
