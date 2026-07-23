# frozen_string_literal: true

require "time"
require_relative "../short_term/stores"

module Llmemory
  module LLM
    # Cumulative LLM token usage per user, persisted in the short-term store
    # under a pseudo-session key (same pattern as ForgetLog).
    class UsageLedger
      SESSION_KEY = "__llm_usage__"

      def initialize(store: nil)
        @store = store || ShortTerm::Stores.build
      end

      def record(user_id, usage, operation:)
        @store.update(user_id, SESSION_KEY) do |state|
          state = normalize(state || default_state)
          case operation.to_sym
          when :invoke
            bucket = state[:invoke]
            state = state.merge(
              invoke: {
                input_tokens: bucket[:input_tokens] + usage.input_tokens,
                output_tokens: bucket[:output_tokens] + usage.output_tokens,
                total_tokens: bucket[:total_tokens] + usage.total_tokens,
                calls: bucket[:calls] + 1
              }
            )
          when :embed
            bucket = state[:embed]
            state = state.merge(
              embed: {
                total_tokens: bucket[:total_tokens] + usage.total_tokens,
                calls: bucket[:calls] + 1
              }
            )
          else
            next state
          end
          state.merge(updated_at: Time.now.iso8601)
        end
        totals(user_id)
      end

      def totals(user_id)
        normalize(load_raw(user_id))
      end

      def reset!(user_id)
        empty = default_state
        @store.save(user_id, SESSION_KEY, stringify(empty))
        empty
      end

      def self.format_text(totals)
        inv = totals[:invoke]
        emb = totals[:embed]
        lines = [
          "LLM TOKEN USAGE:",
          "  Chat/completions: #{inv[:total_tokens]} total (#{inv[:input_tokens]} in, #{inv[:output_tokens]} out, #{inv[:calls]} calls)",
          "  Embeddings: #{emb[:total_tokens]} total (#{emb[:calls]} calls)"
        ]
        lines << "  Last updated: #{totals[:updated_at]}" if totals[:updated_at]
        lines.join("\n")
      end

      private

      def load_raw(user_id)
        state = @store.load(user_id, SESSION_KEY)
        return default_state unless state.is_a?(Hash)
        normalize(state)
      end

      def default_state
        {
          invoke: { input_tokens: 0, output_tokens: 0, total_tokens: 0, calls: 0 },
          embed: { total_tokens: 0, calls: 0 },
          updated_at: nil
        }
      end

      def normalize(state)
        invoke = symbolize_bucket(state[:invoke] || state["invoke"])
        embed = symbolize_bucket(state[:embed] || state["embed"], embed: true)
        {
          invoke: invoke,
          embed: embed,
          updated_at: state[:updated_at] || state["updated_at"]
        }
      end

      def symbolize_bucket(bucket, embed: false)
        bucket = {} unless bucket.is_a?(Hash)
        if embed
          {
            total_tokens: (bucket[:total_tokens] || bucket["total_tokens"] || 0).to_i,
            calls: (bucket[:calls] || bucket["calls"] || 0).to_i
          }
        else
          {
            input_tokens: (bucket[:input_tokens] || bucket["input_tokens"] || 0).to_i,
            output_tokens: (bucket[:output_tokens] || bucket["output_tokens"] || 0).to_i,
            total_tokens: (bucket[:total_tokens] || bucket["total_tokens"] || 0).to_i,
            calls: (bucket[:calls] || bucket["calls"] || 0).to_i
          }
        end
      end

      def stringify(state)
        state.transform_keys(&:to_s).transform_values do |v|
          v.is_a?(Hash) ? v.transform_keys(&:to_s) : v
        end
      end
    end
  end
end
