# frozen_string_literal: true

require_relative "short_term/checkpoint"
require_relative "long_term/file_based"
require_relative "retrieval/engine"

module Llmemory
  class Memory
    DEFAULT_SESSION_ID = "default"
    STATE_KEY_MESSAGES = :messages

    def initialize(user_id:, session_id: DEFAULT_SESSION_ID, checkpoint: nil, long_term: nil, long_term_type: nil, retrieval_engine: nil, api_key: nil)
      @user_id = user_id
      @session_id = session_id
      @checkpoint = checkpoint || ShortTerm::Checkpoint.new(user_id: user_id, session_id: session_id)
      @llm = api_key.to_s.empty? ? nil : Llmemory::LLM.client(api_key: api_key)
      type = long_term_type || Llmemory.configuration.long_term_type || :file_based
      @long_term = long_term || build_long_term(type)
      @retrieval_engine = retrieval_engine || Retrieval::Engine.new(@long_term, llm: @llm)
    end

    def add_message(role:, content:)
      msgs = messages
      msgs << { role: role.to_sym, content: content.to_s }
      save_state(messages: msgs)
      true
    end

    def messages
      state = @checkpoint.restore_state
      return [] unless state.is_a?(Hash)
      list = state[STATE_KEY_MESSAGES] || state[STATE_KEY_MESSAGES.to_s]
      list.is_a?(Array) ? list.dup : []
    end

    def retrieve(query, max_tokens: nil)
      short_context = format_short_term_context(messages)
      long_context = @retrieval_engine.retrieve_for_inference(query, user_id: @user_id, max_tokens: max_tokens)
      combine_contexts(short_context, long_context)
    end

    def consolidate!
      msgs = messages
      return true if msgs.empty?
      conversation_text = msgs.map { |m| format_message(m) }.join("\n")
      @long_term.memorize(conversation_text)
      true
    end

    def clear_session!
      @checkpoint.clear_state
      true
    end

    def compact!(max_bytes: nil)
      max = max_bytes || Llmemory.configuration.compact_max_bytes
      msgs = messages
      current_bytes = messages_byte_size(msgs)
      return false if current_bytes <= max

      old_msgs, recent_msgs = split_messages_by_bytes(msgs, max)
      return false if old_msgs.empty?

      summary = summarize_messages(old_msgs)
      compacted = [{ role: :system, content: summary }] + recent_msgs
      save_state(messages: compacted)
      true
    end

    def user_id
      @user_id
    end

    private

    def summarize_messages(msgs)
      conversation = msgs.map { |m| format_message(m) }.join("\n")
      prompt = <<~PROMPT
        Summarize the following conversation into a concise summary that preserves key information, decisions, and context. Write it as a brief narrative (max 200 words).

        Conversation:
        #{conversation}

        Summary:
      PROMPT
      llm_client.invoke(prompt.strip).to_s.strip
    rescue Llmemory::LLMError
      msgs.map { |m| format_message(m) }.join("\n")[0..500]
    end

    def llm_client
      @llm ||= Llmemory::LLM.client
    end

    def messages_byte_size(msgs)
      msgs.sum { |m| message_byte_size(m) }
    end

    def message_byte_size(msg)
      role = msg[:role] || msg["role"]
      content = msg[:content] || msg["content"]
      role.to_s.bytesize + content.to_s.bytesize
    end

    def split_messages_by_bytes(msgs, max_bytes)
      target_recent_bytes = max_bytes / 2
      recent_bytes = 0
      split_index = msgs.size

      (msgs.size - 1).downto(0) do |i|
        msg_bytes = message_byte_size(msgs[i])
        if recent_bytes + msg_bytes <= target_recent_bytes
          recent_bytes += msg_bytes
          split_index = i
        else
          break
        end
      end

      split_index = [split_index, msgs.size - 1].min
      split_index = [split_index, 1].max if msgs.size > 1

      [msgs[0...split_index], msgs[split_index..]]
    end

    def build_long_term(long_term_type)
      llm_opts = @llm ? { llm: @llm } : {}
      case long_term_type.to_s.to_sym
      when :graph_based
        LongTerm::GraphBased::Memory.new(
          user_id: @user_id,
          storage: LongTerm::GraphBased::Storages.build,
          **llm_opts
        )
      else
        LongTerm::FileBased::Memory.new(user_id: @user_id, storage: LongTerm::FileBased::Storages.build, **llm_opts)
      end
    end

    def save_state(messages:)
      @checkpoint.save_state(STATE_KEY_MESSAGES => messages)
    end

    def format_short_term_context(msgs)
      return "" if msgs.empty?
      lines = ["=== RECENT CONVERSATION ===", ""]
      msgs.each { |m| lines << format_message(m) }
      lines << ""
      lines << "=== END RECENT CONVERSATION ==="
      lines.join("\n")
    end

    # Formats a message hash, handling both symbol and string keys.
    def format_message(m)
      role = m[:role] || m["role"]
      content = m[:content] || m["content"]
      "#{role}: #{content}"
    end

    def combine_contexts(short_context, long_context)
      parts = []
      parts << short_context if short_context.to_s.strip.length.positive?
      parts << long_context.to_s.strip if long_context.to_s.strip.length.positive?
      parts.join("\n\n")
    end
  end
end
