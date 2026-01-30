# frozen_string_literal: true

require_relative "short_term/checkpoint"
require_relative "long_term/file_based"
require_relative "retrieval/engine"

module Llmemory
  class Memory
    DEFAULT_SESSION_ID = "default"
    STATE_KEY_MESSAGES = :messages

    def initialize(user_id:, session_id: DEFAULT_SESSION_ID, checkpoint: nil, long_term: nil, retrieval_engine: nil)
      @user_id = user_id
      @session_id = session_id
      @checkpoint = checkpoint || ShortTerm::Checkpoint.new(user_id: user_id, session_id: session_id)
      @long_term = long_term || LongTerm::FileBased::Memory.new(user_id: user_id, storage: LongTerm::FileBased::Storages.build)
      @retrieval_engine = retrieval_engine || Retrieval::Engine.new(@long_term)
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
      conversation_text = msgs.map { |m| "#{m[:role]}: #{m[:content]}" }.join("\n")
      @long_term.memorize(conversation_text)
      true
    end

    def clear_session!
      @checkpoint.clear_state
      true
    end

    def user_id
      @user_id
    end

    private

    def save_state(messages:)
      @checkpoint.save_state(STATE_KEY_MESSAGES => messages)
    end

    def format_short_term_context(msgs)
      return "" if msgs.empty?
      lines = ["=== RECENT CONVERSATION ===", ""]
      msgs.each do |m|
        role = m[:role] || m["role"]
        content = m[:content] || m["content"]
        lines << "#{role}: #{content}"
      end
      lines << ""
      lines << "=== END RECENT CONVERSATION ==="
      lines.join("\n")
    end

    def combine_contexts(short_context, long_context)
      parts = []
      parts << short_context if short_context.to_s.strip.length.positive?
      parts << long_context.to_s.strip if long_context.to_s.strip.length.positive?
      parts.join("\n\n")
    end
  end
end
