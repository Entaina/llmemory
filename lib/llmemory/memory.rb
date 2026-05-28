# frozen_string_literal: true

require_relative "short_term/checkpoint"
require_relative "short_term/pruner"
require_relative "long_term/file_based"
require_relative "retrieval/engine"

module Llmemory
  class Memory
    DEFAULT_SESSION_ID = "default"
    STATE_KEY_MESSAGES = :messages

    def initialize(user_id:, session_id: DEFAULT_SESSION_ID, checkpoint: nil, long_term: nil, long_term_type: nil, retrieval_engine: nil, working_memory: nil, episodic: nil, procedural: nil, api_key: nil)
      @user_id = user_id
      @session_id = session_id
      @checkpoint = checkpoint || ShortTerm::Checkpoint.new(user_id: user_id, session_id: session_id)
      @working_memory = working_memory
      @episodic = episodic
      @procedural = procedural
      @llm = api_key.to_s.empty? ? nil : Llmemory::LLM.client(api_key: api_key)
      type = long_term_type || Llmemory.configuration.long_term_type || :file_based
      @long_term = long_term || build_long_term(type)
      @retrieval_engine = retrieval_engine || Retrieval::Engine.new(@long_term, llm: @llm)
    end

    # Structured working memory for this session (CoALA working memory),
    # parallel to the message checkpoint. Lazily built.
    def working_memory
      @working_memory ||= WorkingMemory.new(user_id: @user_id, session_id: @session_id)
    end

    # Episodic long-term memory (CoALA): records and retrieves agent trajectories.
    # Additive — coexists with the semantic store (file/graph). Lazily built.
    def episodic
      @episodic ||= LongTerm::Episodic::Memory.new(user_id: @user_id)
    end

    # Procedural long-term memory (Voyager-style skill library). Lazily built.
    def procedural
      @procedural ||= LongTerm::Procedural::Memory.new(user_id: @user_id)
    end

    # Reflects over recent episodes and writes distilled insights to the
    # semantic store (file/graph) with provenance back to source episodes.
    def reflect!(window: 10, category: "insights")
      Reflection::Reflector.new(episodic: episodic, semantic: @long_term, llm: @llm)
        .reflect(window: window, category: category)
    end

    # Reasoning action: render a prompt from working memory, call the LLM, write
    # the result back. Composable; does not touch long-term memory.
    def reason(template:, into: Actions::Reason::DEFAULT_SLOT, parse: nil)
      Actions::Reason.call(working_memory: working_memory, template: template, into: into, parse: parse, llm: @llm)
    end

    def add_message(role:, content:)
      msgs = messages
      msgs << { role: role.to_sym, content: content.to_s }
      save_state(messages: msgs, **preserved_flush_state)
      true
    end

    def messages
      state = @checkpoint.restore_state
      return [] unless state.is_a?(Hash)
      list = state[STATE_KEY_MESSAGES] || state[STATE_KEY_MESSAGES.to_s]
      list = list.is_a?(Array) ? list.dup : []
      sanitize_messages(list)
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
      save_state(messages: pruned, **preserved_flush_state)
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

      flushed = flush_memory_before_compaction!(msgs)

      old_msgs, recent_msgs = split_messages_by_bytes(msgs, max)
      return false if old_msgs.empty?

      summary = summarize_messages(old_msgs)
      compacted = [{ role: :system, content: summary }] + recent_msgs
      state = restore_state_for_save
      flush_ts = flushed ? Time.now : (state[:last_flush_at] || state["last_flush_at"])
      save_state(messages: compacted, last_compact_at: Time.now, last_flush_at: flush_ts)
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

    def with_overflow_recovery(max_retries: 2, &block)
      return yield unless Llmemory.configuration.overflow_recovery_enabled
      return yield unless block_given?

      retries = 0
      begin
        yield
      rescue Llmemory::LLMError => e
        msg = e.message.to_s.downcase
        overflow = msg.include?("context") || msg.include?("token") || msg.include?("overflow") || msg.include?("limit")
        raise unless overflow && retries < max_retries

        prune! if Llmemory.configuration.prune_tool_results_enabled
        compact!
        retries += 1
        retry
      end
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
      return false unless Llmemory.configuration.memory_flush_enabled
      return false if msgs.empty?
      return false if estimated_tokens(msgs) < Llmemory.configuration.memory_flush_threshold_tokens

      state = restore_state_for_save
      last_compact = state[:last_compact_at] || state["last_compact_at"]
      window = Llmemory.configuration.flush_once_per_cycle_seconds.to_i

      if last_compact
        t = last_compact.is_a?(Time) ? last_compact : Time.parse(last_compact.to_s)
        return false if (Time.now - t).to_i < window
      end

      consolidate!
      true
    end

    def sanitize_messages(msgs)
      return msgs unless Llmemory.configuration.message_sanitizer_enabled

      sanitizer = ShortTerm::MessageSanitizer.new
      sanitizer.sanitize!(msgs)
    end

    def restore_state_for_save
      @checkpoint.restore_state || {}
    end

    def preserved_flush_state
      state = restore_state_for_save
      {}.tap do |h|
        h[:last_flush_at] = state[:last_flush_at] || state["last_flush_at"] if state[:last_flush_at] || state["last_flush_at"]
        h[:last_compact_at] = state[:last_compact_at] || state["last_compact_at"] if state[:last_compact_at] || state["last_compact_at"]
      end
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

    def save_state(messages:, last_flush_at: nil, last_compact_at: nil)
      state = { STATE_KEY_MESSAGES => messages, last_activity_at: Time.now }
      state[:last_flush_at] = last_flush_at if last_flush_at
      state[:last_compact_at] = last_compact_at if last_compact_at
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
