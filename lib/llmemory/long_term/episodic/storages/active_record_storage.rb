# frozen_string_literal: true

require "json"
require "securerandom"
require "time"
require_relative "base"
require_relative "../../../crypto/field_helpers"

module Llmemory
  module LongTerm
    module Episodic
      module Storages
        # ActiveRecord backend. Stores each episode as a JSONB `data` document;
        # AR auto-deserializes jsonb to a Hash (string keys), which Episode.from_h
        # handles. Mirrors the file-based ActiveRecordStorage pattern.
        class ActiveRecordStorage < Base
          include Llmemory::Crypto::FieldHelpers

          def initialize(cipher: nil)
            @cipher = cipher || Llmemory.build_cipher
            self.class.load_models!
          end

          def self.load_models!
            return if @models_loaded
            require "active_record"
            require_relative "active_record_models"
            @models_loaded = true
          end

          def save_episode(user_id, episode)
            id = episode[:id] || episode["id"] || "ep_#{SecureRandom.hex(8)}"
            data = stringify(episode).merge("id" => id, "user_id" => user_id)
            data["created_at"] ||= Time.now.utc.iso8601
            rec = LlmemoryEpisode.find_or_initialize_by(id: id)
            rec.user_id = user_id
            rec.data = cipher.enabled? ? enc_json(data) : data
            rec.search_text = enc(searchable_text(data))
            rec.created_at ||= Time.current
            rec.save!
            id
          end

          def get_episode(user_id, id)
            rec = LlmemoryEpisode.find_by(user_id: user_id, id: id)
            return nil unless rec

            decode_data(rec.data)
          end

          def list_episodes(user_id, limit: nil, offset: nil)
            scope = LlmemoryEpisode.where(user_id: user_id, archived_at: nil).order(created_at: :desc)
            scope = scope.limit(limit) if limit && limit.to_i.positive?
            scope = scope.offset(offset) if offset && offset.to_i.positive?
            scope.map { |r| decode_data(r.data) }
          end

          def search_episodes(user_id, query)
            token_scope(LlmemoryEpisode.where(user_id: user_id, archived_at: nil), "search_text", query)
              .order(created_at: :desc).map { |r| decode_data(r.data) }
          end

          def count_episodes(user_id)
            LlmemoryEpisode.where(user_id: user_id, archived_at: nil).count
          end

          def delete_episodes(user_id, ids)
            LlmemoryEpisode.where(user_id: user_id, id: Array(ids).map(&:to_s)).delete_all
          end

          def archive_episodes(user_id, ids)
            LlmemoryEpisode.where(user_id: user_id, id: Array(ids).map(&:to_s), archived_at: nil)
              .update_all(archived_at: Time.current)
          end

          def expired_episode_ids(user_id, cutoff:)
            LlmemoryEpisode.where(user_id: user_id, archived_at: nil).where("created_at < ?", cutoff).pluck(:id)
          end

          def list_users
            LlmemoryEpisode.distinct.pluck(:user_id)
          end

          private

          def token_scope(scope, column, query)
            tokens = Llmemory::Tokenizer.tokenize(query)
            return scope if tokens.empty?
            clause = tokens.map { "LOWER(#{column}) LIKE LOWER(?)" }.join(" OR ")
            scope.where(clause, *tokens.map { |t| "%#{t}%" })
          end

          def stringify(hash)
            JSON.parse(JSON.generate(hash))
          end

          def searchable_text(data)
            parts = [data["summary"], data["outcome"]]
            Array(data["steps"]).each do |s|
              next unless s.is_a?(Hash)
              parts << s["observation"] << s["action"] << s["result"]
            end
            parts.compact.join("\n")
          end

          def decode_data(raw)
            return raw.transform_keys(&:to_sym) if raw.is_a?(Hash)
            return dec_json(raw) if raw.is_a?(String) && cipher.encrypted?(raw)

            raw
          end
        end
      end
    end
  end
end
