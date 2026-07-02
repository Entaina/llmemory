# frozen_string_literal: true

require "json"
require "securerandom"
require "time"
require_relative "base"
require_relative "../../../crypto/field_helpers"

module Llmemory
  module LongTerm
    module Procedural
      module Storages
        # ActiveRecord backend. Stores each skill as a JSONB `data` document; AR
        # auto-deserializes jsonb to a Hash (string keys), which Skill.from_h
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

          def save_skill(user_id, skill)
            id = skill[:id] || skill["id"] || "skill_#{SecureRandom.hex(8)}"
            data = stringify(skill).merge("id" => id, "user_id" => user_id)
            data["created_at"] ||= Time.now.utc.iso8601
            rec = LlmemorySkill.find_or_initialize_by(id: id)
            rec.user_id = user_id
            rec.data = cipher.enabled? ? enc_json(data) : data
            rec.search_text = enc(searchable_text(data))
            rec.created_at ||= Time.current
            rec.save!
            id
          end

          def get_skill(user_id, id)
            rec = LlmemorySkill.find_by(user_id: user_id, id: id)
            return nil unless rec

            decode_data(rec.data)
          end

          def list_skills(user_id, limit: nil, offset: nil)
            scope = LlmemorySkill.where(user_id: user_id, archived_at: nil).order(created_at: :desc)
            scope = scope.limit(limit) if limit && limit.to_i.positive?
            scope = scope.offset(offset) if offset && offset.to_i.positive?
            scope.map { |r| decode_data(r.data) }
          end

          def search_skills(user_id, query)
            token_scope(LlmemorySkill.where(user_id: user_id, archived_at: nil), "search_text", query)
              .order(created_at: :desc).map { |r| decode_data(r.data) }
          end

          def find_skills_by_name(user_id, name)
            if cipher.enabled?
              LlmemorySkill.where(user_id: user_id, archived_at: nil).map { |r| decode_data(r.data) }
                .select { |s| (s[:name] || s["name"]).to_s == name.to_s }
            else
              LlmemorySkill.where(user_id: user_id, archived_at: nil).where("data->>'name' = ?", name.to_s).map(&:data)
            end
          end

          def record_outcome(user_id, skill_id, success:)
            rec = LlmemorySkill.find_by(user_id: user_id, id: skill_id)
            return nil unless rec
            data = decode_data(rec.data) || {}
            key = success ? :success_count : :failure_count
            data[key] = (data[key] || 0).to_i + 1
            data[:updated_at] = Time.now.utc.iso8601
            rec.data = cipher.enabled? ? enc_json(data) : data
            rec.search_text = enc(searchable_text(data))
            rec.save!
            data
          end

          def count_skills(user_id)
            LlmemorySkill.where(user_id: user_id, archived_at: nil).count
          end

          def delete_skills(user_id, ids)
            LlmemorySkill.where(user_id: user_id, id: Array(ids).map(&:to_s)).delete_all
          end

          def archive_skills(user_id, ids)
            LlmemorySkill.where(user_id: user_id, id: Array(ids).map(&:to_s), archived_at: nil)
              .update_all(archived_at: Time.current)
          end

          def expired_skill_ids(user_id, cutoff:)
            LlmemorySkill.where(user_id: user_id, archived_at: nil).where("created_at < ?", cutoff).pluck(:id)
          end

          def list_users
            LlmemorySkill.distinct.pluck(:user_id)
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
            h = data.is_a?(Hash) ? data : {}
            [h["name"] || h[:name], h["description"] || h[:description], h["body"] || h[:body]].compact.join("\n")
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
