# frozen_string_literal: true

require_relative "base"

module Llmemory
  module LongTerm
    module Episodic
      module Storages
        class MemoryStorage < Base
          def initialize
            @episodes = Hash.new { |h, k| h[k] = [] }
            @seq = 0
          end

          def save_episode(user_id, episode)
            @seq += 1
            id = episode[:id] || episode["id"] || "ep_#{@seq}"
            record = symbolize(episode).merge(id: id, user_id: user_id)
            record[:created_at] ||= Time.now
            @episodes[user_id] << record
            id
          end

          def get_episode(user_id, id)
            @episodes[user_id].find { |e| e[:id] == id }
          end

          def list_episodes(user_id, limit: nil, offset: nil)
            sorted = active_episodes(user_id).sort_by { |e| as_time(e[:created_at]) }.reverse
            sorted = sorted.drop(offset.to_i) if offset && offset.to_i.positive?
            limit && limit.to_i.positive? ? sorted.first(limit.to_i) : sorted
          end

          def search_episodes(user_id, query)
            return list_episodes(user_id) if query.to_s.strip.empty?
            active_episodes(user_id).select { |e| Llmemory::Tokenizer.matches?(episode_text(e), query) }
          end

          def count_episodes(user_id)
            active_episodes(user_id).size
          end

          def delete_episodes(user_id, ids)
            ids = Array(ids).map(&:to_s)
            before = @episodes[user_id].size
            @episodes[user_id].reject! { |e| ids.include?(e[:id].to_s) }
            before - @episodes[user_id].size
          end

          def archive_episodes(user_id, ids)
            ids = Array(ids).map(&:to_s)
            count = 0
            @episodes[user_id].each do |e|
              next unless ids.include?(e[:id].to_s)
              next if e[:archived_at]
              e[:archived_at] = Time.now
              count += 1
            end
            count
          end

          def expired_episode_ids(user_id, cutoff:)
            active_episodes(user_id)
              .select { |e| as_time(e[:created_at]) < cutoff }
              .map { |e| e[:id].to_s }
          end

          def list_users
            @episodes.keys
          end

          private

          def active_episodes(user_id)
            @episodes[user_id].reject { |e| e[:archived_at] }
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

          def episode_text(episode)
            parts = [episode[:summary], episode[:outcome]]
            Array(episode[:steps]).each do |s|
              next unless s.is_a?(Hash)
              parts << (s[:observation] || s["observation"])
              parts << (s[:action] || s["action"])
              parts << (s[:result] || s["result"])
            end
            parts.compact.join("\n")
          end
        end
      end
    end
  end
end
