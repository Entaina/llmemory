# frozen_string_literal: true

module Llmemory
  module ShortTerm
    class Pruner
      DEFAULT_PRUNABLE_ROLES = %i[tool tool_result].freeze
      PLACEHOLDER = "[Tool result pruned]"

      def initialize(prunable_roles: nil, soft_trim_max_bytes: 2048, soft_trim_head_ratio: 0.4, soft_trim_tail_ratio: 0.2)
        @prunable_roles = prunable_roles || DEFAULT_PRUNABLE_ROLES.map(&:to_s)
        @soft_trim_max_bytes = soft_trim_max_bytes
        @head_ratio = soft_trim_head_ratio
        @tail_ratio = soft_trim_tail_ratio
      end

      def prune!(messages, mode: :soft_trim)
        return messages.dup if messages.empty?

        messages.map do |msg|
          if prunable?(msg)
            apply_prune(msg, mode)
          else
            msg.dup
          end
        end
      end

      private

      def prunable?(msg)
        role = (msg[:role] || msg["role"]).to_s
        @prunable_roles.include?(role)
      end

      def apply_prune(msg, mode)
        content = (msg[:content] || msg["content"]).to_s
        new_content = case mode.to_s.to_sym
        when :hard_clear
          PLACEHOLDER
        when :soft_trim
          soft_trim(content)
        else
          content
        end

        result = msg.dup
        result[:content] = new_content if result.key?(:content)
        result["content"] = new_content if result.key?("content")
        result
      end

      def soft_trim(content)
        return content if content.bytesize <= @soft_trim_max_bytes

        head_bytes = (@soft_trim_max_bytes * @head_ratio).to_i
        tail_bytes = (@soft_trim_max_bytes * @tail_ratio).to_i

        head = utf8_safe_byteslice(content, 0, head_bytes)
        tail = if content.bytesize > (head_bytes + tail_bytes)
                 utf8_safe_byteslice(content, -tail_bytes, tail_bytes)
               else
                 ""
               end

        "#{head}\n...\n#{tail}"
      end

      def utf8_safe_byteslice(str, start, length = nil)
        slice = length.nil? ? str.byteslice(start) : str.byteslice(start, length)
        return "" if slice.nil?

        slice.force_encoding(str.encoding)
        slice.scrub
      end
    end
  end
end
