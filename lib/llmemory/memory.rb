# frozen_string_literal: true

require_relative "short_term/checkpoint"
require_relative "short_term/pruner"
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
      msgs = pruned_messages
      short_context = format_short_term_context(msgs)
      long_context = @retrieval_engine.retrieve_for_inference(query, user_id: @user_id, max_tokens: max_tokens)
      combine_contexts(short_context, long_context)
    end

    def recall_for(query: nil, max_tokens: nil)
      return "" unless Llmemory.configuration.auto_recall_enabled

      effective_query = query || last_user_message
      return "" if effective_query.to_s.strip.empty?

      retrieve(effective_query, max_tokens: max_tokens)
    end

    def last_user_message
      msgs = messages
      idx = msgs.rindex { |m| (m[:role] || m["role"]).to_s == "user" }
      idx ? (msgs[idx][:content] || msgs[idx]["content"]).to_s : ""
    end

    def prune!(mode: nil)
      return false unless Llmemory.configuration.prune_tool_results_enabled

      msgs = messages
      return false if msgs.empty?

      mode ||= Llmemory.configuration.prune_tool_results_mode
      pruner = ShortTerm::Pruner.new(
        soft_trim_max_bytes: Llmemory.configuration.prune_tool_results_max_bytes
      )
      pruned = pruner.prune!(msgs, mode: mode)
      save_state(messages: pruned)
      true
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

      flush_memory_before_compaction!(msgs)

      old_msgs, recent_msgs = split_messages_by_bytes(msgs, max)
      return false if old_msgs.empty?

      summary = summarize_messages(old_msgs)
      compacted = [{ role: :system, content: summary }] + recent_msgs
      save_state(messages: compacted)
      true
    end

    def maybe_flush_memory!
      return false unless Llmemory.configuration.memory_flush_enabled
      msgs = messages
      return false if msgs.empty?
      return false if estimated_tokens(msgs) < Llmemory.configuration.memory_flush_threshold_tokens

      consolidate!
    end

    def context_tokens
      estimated_tokens(messages)
    end

    def should_auto_consolidate?
      ctx = context_tokens
      threshold = Llmemory.configuration.context_window_tokens - Llmemory.configuration.reserve_tokens
      ctx >= threshold
    end

    def should_compact?
      ctx = context_tokens
      threshold = Llmemory.configuration.context_window_tokens - Llmemory.configuration.reserve_tokens
      ctx >= threshold
    end

    def check_context_window!
      return false if messages.empty?

      flushed = false
      if should_auto_consolidate? && Llmemory.configuration.memory_flush_enabled
        consolidate!
        flushed = true
      end

      compacted = false
      if should_compact?
        compacted = compact!
      end

      flushed || compacted
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

    def flush_memory_before_compaction!(msgs)
      return unless Llmemory.configuration.memory_flush_enabled
      return if msgs.empty?
      return if estimated_tokens(msgs) < Llmemory.configuration.memory_flush_threshold_tokens

      consolidate!
    end

    def estimated_tokens(msgs)
      (messages_byte_size(msgs) / 4.0).ceil
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
      state = { STATE_KEY_MESSAGES => messages, last_activity_at: Time.now }
      @checkpoint.save_state(state)
    end

    def pruned_messages
      return messages unless Llmemory.configuration.prune_tool_results_enabled

      pruner = ShortTerm::Pruner.new(
        soft_trim_max_bytes: Llmemory.configuration.prune_tool_results_max_bytes
      )
      pruner.prune!(messages, mode: Llmemory.configuration.prune_tool_results_mode)
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
