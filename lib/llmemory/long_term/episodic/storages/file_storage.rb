# frozen_string_literal: true

require "fileutils"
require "json"
require "time"
require_relative "base"

module Llmemory
  module LongTerm
    module Episodic
      module Storages
        class FileStorage < Base
          def initialize(base_path: nil)
            @base_path = base_path || Llmemory.configuration.long_term_storage_path || "./llmemory_data"
            @base_path = File.expand_path(@base_path)
          end

          def save_episode(user_id, episode)
            id = episode[:id] || episode["id"] || "ep_#{next_seq(user_id)}"
            data = stringify_for_json(episode).merge("id" => id, "user_id" => user_id)
            data["created_at"] ||= Time.now.iso8601
            File.write(episode_path(user_id, id), JSON.generate(data))
            id
          end

          def get_episode(user_id, id)
            path = episode_path(user_id, id)
            return nil unless File.file?(path)
            load_episode(path)
          end

          def list_episodes(user_id, limit: nil)
            sorted = all_episodes(user_id).sort_by { |e| e[:created_at] }.reverse
            limit && limit.to_i.positive? ? sorted.first(limit.to_i) : sorted
          end

          def search_episodes(user_id, query)
            q = query.to_s.downcase
            return list_episodes(user_id) if q.strip.empty?
            all_episodes(user_id).select { |e| episode_text(e).downcase.include?(q) }
          end

          def count_episodes(user_id)
            dir = user_path(user_id, "episodes")
            return 0 unless Dir.exist?(dir)
            Dir.children(dir).count { |f| f.end_with?(".json") }
          end

          def list_users
            return [] unless Dir.exist?(@base_path)
            Dir.children(@base_path).select { |d| Dir.exist?(File.join(@base_path, d, "episodes")) }
          end

          private

          def all_episodes(user_id)
            dir = user_path(user_id, "episodes")
            return [] unless Dir.exist?(dir)
            Dir.children(dir).select { |f| f.end_with?(".json") }.map { |f| load_episode(File.join(dir, f)) }.compact
          end

          def load_episode(path)
            data = JSON.parse(File.read(path), symbolize_names: true)
            data[:created_at] = parse_time(data[:created_at])
            data
          rescue JSON::ParserError
            nil
          end

          def episode_text(episode)
            parts = [episode[:summary], episode[:outcome]]
            Array(episode[:steps]).each do |s|
              next unless s.is_a?(Hash)
              parts << s[:observation] << s[:action] << s[:result]
            end
            parts.compact.join("\n")
          end

          def stringify_for_json(episode)
            JSON.parse(JSON.generate(episode))
          end

          def user_path(user_id, *parts)
            safe = user_id.to_s.gsub(%r{[^\w\-.]}, "_")
            File.join(@base_path, safe, *parts)
          end

          def episode_path(user_id, id)
            dir = user_path(user_id, "episodes")
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
            meta["episode_id_seq"] = (meta["episode_id_seq"] || 0) + 1
            File.write(path, JSON.generate(meta))
            meta["episode_id_seq"]
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
