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

          def list_skills(user_id, limit: nil, offset: nil)
            sorted = active_skills(user_id).sort_by { |s| as_time(s[:created_at]) }.reverse
            sorted = sorted.drop(offset.to_i) if offset && offset.to_i.positive?
            limit && limit.to_i.positive? ? sorted.first(limit.to_i) : sorted
          end

          def search_skills(user_id, query)
            return list_skills(user_id) if query.to_s.strip.empty?
            active_skills(user_id).select { |s| Llmemory::Tokenizer.matches?(skill_text(s), query) }
          end

          def find_skills_by_name(user_id, name)
            active_skills(user_id).select { |s| s[:name].to_s == name.to_s }
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
            active_skills(user_id).size
          end

          def delete_skills(user_id, ids)
            ids = Array(ids).map(&:to_s)
            before = @skills[user_id].size
            @skills[user_id].reject! { |s| ids.include?(s[:id].to_s) }
            before - @skills[user_id].size
          end

          def archive_skills(user_id, ids)
            ids = Array(ids).map(&:to_s)
            count = 0
            @skills[user_id].each do |s|
              next unless ids.include?(s[:id].to_s)
              next if s[:archived_at]
              s[:archived_at] = Time.now
              count += 1
            end
            count
          end

          def expired_skill_ids(user_id, cutoff:)
            active_skills(user_id)
              .select { |s| as_time(s[:created_at]) < cutoff }
              .map { |s| s[:id].to_s }
          end

          def list_users
            @skills.keys
          end

          private

          def active_skills(user_id)
            @skills[user_id].reject { |s| s[:archived_at] }
          end

          def as_time(value)
            return Time.now if value.nil?
            return value if value.is_a?(Time)
            Time.parse(value.to_s)
          rescue ArgumentError
            Time.now
          end

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
