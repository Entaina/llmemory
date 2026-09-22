# frozen_string_literal: true

require_relative "short_term/checkpoint"
require_relative "short_term/pruner"
require_relative "long_term/file_based"
require_relative "retrieval/engine"

module Llmemory
  class Memory
    DEFAULT_SESSION_ID = "default"
    STATE_KEY_MESSAGES = :messages

    def initialize(user_id:, session_id: DEFAULT_SESSION_ID, checkpoint: nil, long_term: nil, long_term_type: nil,
                   retrieval_engine: nil, working_memory: nil, episodic: nil, procedural: nil, api_key: nil,
                   encryption_key: :inherit, trace_store: nil, compact_strategy: nil, forget_log: nil,
                   memory_mode: nil)
      @user_id = user_id
      @session_id = session_id
      @memory_mode = ZeroMem::Mode.normalize(memory_mode || Llmemory.configuration.memory_mode)
      @trace_store = trace_store
      if @trace_store.nil? && (zero_mem_enabled? || shadow_write_enabled?)
        @trace_store = ZeroMem::Storages.build
      end
      @compact_strategy = compact_strategy
      @forget_log = forget_log
      @trace_indexer = @trace_store ? ZeroMem::Indexer.new(@trace_store) : nil
      resolved_key = encryption_key == :inherit ? nil : encryption_key
      @cipher = Llmemory.build_cipher(resolved_key)
      if checkpoint
        @checkpoint = checkpoint
        @short_term_store = checkpoint.store
      else
        @short_term_store = build_short_term_store(@cipher)
        @checkpoint = ShortTerm::Checkpoint.new(
          user_id: user_id,
          session_id: session_id,
          store: @short_term_store,
          cipher: @cipher
        )
      end
      @working_memory = working_memory
      @episodic = episodic
      @procedural = procedural
      @api_key = api_key unless api_key.to_s.empty?
      type = long_term_type || Llmemory.configuration.long_term_type || :file_based
      @long_term = long_term || build_long_term(type)
      @retrieval_engine = retrieval_engine || Retrieval::Engine.new(
        Retrieval::MultiSource.new(primary: @long_term, memory: self),
        llm: tracked_llm_client,
        feedback: Retrieval::FeedbackStore.new(store: @short_term_store)
      )
    end

    # Structured working memory for this session (CoALA working memory),
    # parallel to the message checkpoint. Lazily built.
    def working_memory
      @working_memory ||= WorkingMemory.new(
        user_id: @user_id,
        session_id: @session_id,
        store: @short_term_store
      )
    end

    # Episodic long-term memory (CoALA): records and retrieves agent trajectories.
    # Additive — coexists with the semantic store (file/graph). Lazily built.
    def episodic
      @episodic ||= LongTerm::Episodic::Memory.new(
        user_id: @user_id,
        storage: LongTerm::Episodic::Storages.build(cipher: @cipher),
        cipher: @cipher,
        forget_log_store: @short_term_store
      )
    end

    # Procedural long-term memory (Voyager-style skill library). Lazily built.
    def procedural
      @procedural ||= LongTerm::Procedural::Memory.new(
        user_id: @user_id,
        storage: LongTerm::Procedural::Storages.build(cipher: @cipher),
        cipher: @cipher,
        forget_log_store: @short_term_store
      )
    end

    # Reflects over recent episodes and writes distilled insights to the
    # semantic store (file/graph) with provenance back to source episodes.
    def reflect!(window: 10, category: "insights")
      deny_generative!(:reflect!) if zero_mem_strict?
      Reflection::Reflector.new(episodic: episodic, semantic: @long_term, llm: tracked_llm_client)
        .reflect(window: window, category: category)
    end

    # Reasoning action: render a prompt from working memory, call the LLM, write
    # the result back. Composable; does not touch long-term memory.
    def reason(template:, into: Actions::Reason::DEFAULT_SLOT, parse: nil)
      Actions::Reason.call(working_memory: working_memory, template: template, into: into, parse: parse, llm: tracked_llm_client)
    end

    # Mines recent episodes for reusable skills (Voyager-style). Human-in-the-loop
    # by default: returns skill proposals and writes nothing. With
    # `auto_register: true`, registers them in procedural memory (with provenance
    # back to the source episodes) and returns the new skill ids.
    def mine_skills!(window: SkillMining::Miner::DEFAULT_WINDOW, outcomes: nil, auto_register: false)
      deny_generative!(:mine_skills!) if zero_mem_strict?
      SkillMining::Miner.new(episodic: episodic, procedural: procedural, llm: tracked_llm_client)
        .mine(window: window, outcomes: outcomes, auto_register: auto_register)
    end

    # Cognitive maintenance pass: consolidate -> reflect -> mine skills -> expire,
    # in one step, closing the CoALA learning loop. Each step is isolated; a
    # failure in one is captured in the report and never aborts the others.
    def maintain!(**opts)
      Maintenance::CognitivePass.run!(
        @user_id,
        memory: self, episodic: episodic, procedural: procedural, semantic: @long_term, llm: tracked_llm_client,
        **opts
      )
    end

    def add_message(role:, content:, occurred_at: nil, boundary_id: nil, metadata: nil, idempotency_key: nil)
      if @trace_store
        record_trace(
          role: role,
          content: content,
          occurred_at: occurred_at,
          boundary_id: boundary_id,
          metadata: metadata,
          idempotency_key: idempotency_key,
          add_to_checkpoint: true
        )
      else
        append_message_to_checkpoint(role: role, content: content, occurred_at: occurred_at)
      end
      true
    end

    # Persists an immutable trace before updating the checkpoint (Zero-Mem source of truth).
    def record_trace(role:, content:, occurred_at: nil, boundary_id: nil, metadata: nil, idempotency_key: nil,
                     state_key: nil, valid_from: nil, valid_to: nil, supersedes_trace_id: nil, source: :explicit,
                     add_to_checkpoint: true)
      raise ConfigurationError, "trace_store is not configured" unless @trace_store

      parts = split_trace_parts(content)
      if parts.size > 1
        return parts.each_with_index.map do |part, idx|
          part_key = idempotency_key ? "#{idempotency_key}#p#{idx + 1}" : nil
          part_meta = (metadata || {}).merge(part_of: idempotency_key, part_index: idx + 1, part_count: parts.size)
          record_trace(
            role: role, content: part, occurred_at: occurred_at, boundary_id: boundary_id,
            metadata: part_meta, idempotency_key: part_key, state_key: state_key,
            valid_from: valid_from, valid_to: valid_to, supersedes_trace_id: supersedes_trace_id,
            source: source, add_to_checkpoint: add_to_checkpoint && idx.zero?
          )
        end.last
      end

      if idempotency_key && (existing = @trace_store.find_by_idempotency_key(@user_id, idempotency_key))
        return existing.id
      end

      sequence = @trace_store.next_sequence(@user_id, @session_id)
      trace = ZeroMem::Trace.build(
        user_id: @user_id,
        session_id: @session_id,
        role: role,
        content: content,
        sequence: sequence,
        boundary_id: boundary_id,
        occurred_at: occurred_at,
        metadata: metadata,
        idempotency_key: idempotency_key
      )

      index_stats = {}
      Llmemory::Instrumentation.instrument(
        :trace_write,
        user_id: @user_id,
        session_id: @session_id,
        trace_id: trace.id,
        sequence: sequence,
        role: trace.role,
        maintenance_fanout: state_key ? 2 : 1
      ) do
        @trace_store.write_trace(trace)
        if state_key
          effective_from = valid_from || trace.occurred_at
          if supersedes_trace_id
            @trace_store.close_open_state_links(
              @user_id,
              state_key,
              valid_to: effective_from,
              except_trace_id: trace.id
            )
          end
          link = ZeroMem::TraceStateLink.build(
            user_id: @user_id,
            state_key: state_key,
            trace_id: trace.id,
            valid_from: effective_from,
            valid_to: valid_to,
            supersedes_trace_id: supersedes_trace_id,
            source: source
          )
          @trace_store.write_state_link(link)
          Llmemory::Instrumentation.instrument(
            :zero_mem_state_update,
            user_id: @user_id,
            state_key: state_key,
            trace_id: trace.id,
            supersedes_trace_id: supersedes_trace_id
          )
        end
        index_stats = @trace_indexer.after_trace_write(
          trace: trace,
          state_link: !state_key.nil?
        )
      end

      if add_to_checkpoint
        append_message_to_checkpoint(
          role: trace.role,
          content: trace.content,
          occurred_at: trace.occurred_at,
          trace_id: trace.id
        )
      end
      trace.id
    end

    def retrieve_evidence(query, top_k: nil, max_tokens: nil, boundary: nil, explain: false, current_trace_id: nil,
                          **opts)
      raise ConfigurationError, "retrieve_evidence requires memory_mode :zero_mem or :hybrid" unless zero_mem_enabled?
      raise ConfigurationError, "trace_store is not configured" unless @trace_store

      invoke_before = generative_invoke_calls
      result = zero_mem_engine.retrieve_evidence(
        query,
        top_k: top_k,
        max_tokens: max_tokens,
        boundary: boundary,
        explain: explain,
        current_trace_id: current_trace_id,
        **opts
      )
      compliant = generative_invoke_delta(invoke_before).zero?
      result.metrics[:zero_mem_compliant] = compliant if zero_mem_strict?
      result
    end

    def calibrate_answer(answer, evidence_result:)
      ZeroMem::AnswerCalibrator.new.calibrate(answer, evidence_result: evidence_result)
    end

    def forget_traces!(trace_ids, reason: nil)
      return false unless @trace_store

      ids = Array(trace_ids).map(&:to_s)
      ids.each { |id| @trace_store.archive_trace(@user_id, id) }
      forget_log.record(
        @user_id,
        memory_type: ZeroMem::MEMORY_TYPE,
        ids: ids,
        reason: reason
      )
      true
    end

    attr_reader :trace_store

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

      if hybrid? && @trace_store
        return retrieve_hybrid(query, short_context, max_tokens)
      end

      if zero_mem_strict? && @trace_store
        invoke_before = generative_invoke_calls
        evidence_context = zero_mem_engine.to_context(query, max_tokens: max_tokens)
        combined = combine_contexts(short_context, evidence_context)
        compliant = generative_invoke_delta(invoke_before).zero?
        Llmemory::Instrumentation.instrument(
          :retrieve,
          query_chars: query.to_s.length,
          zero_mem_compliant: compliant
        )
        return combined
      end

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
      deny_generative!(:consolidate!) if zero_mem_strict?
      msgs = messages
      return true if msgs.empty?

      chunk_limit = Llmemory.configuration.consolidation_chunk_tokens.to_i
      if chunk_limit.positive? && message_batch_tokens(msgs) > chunk_limit
        message_chunks(msgs, chunk_limit).each do |chunk|
          conversation_text = chunk.map { |m| format_message(m) }.join("\n")
          reference_time = consolidation_reference_time(chunk)
          @long_term.memorize(
            conversation_text,
            reference_time: reference_time,
            source_traces: consolidation_source_traces(chunk),
            known_facts: consolidation_known_facts(conversation_text)
          )
        end
      else
        conversation_text = msgs.map { |m| format_message(m) }.join("\n")
        reference_time = consolidation_reference_time(msgs)
        @long_term.memorize(
          conversation_text,
          reference_time: reference_time,
          source_traces: consolidation_source_traces(msgs),
          known_facts: consolidation_known_facts(conversation_text)
        )
      end
      true
    end

    def clear_session!
      @checkpoint.clear_state
      working_memory.clear!
      true
    end

    def compact!(max_bytes: nil)
      max = max_bytes || Llmemory.configuration.compact_max_bytes
      if trace_backed? || zero_mem_strict?
        if hybrid? && !zero_mem_strict?
          flush_memory_before_compaction!(messages)
        end
        return compact_trace_deterministic!(max)
      end

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
      return false if zero_mem_strict?
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

      if zero_mem_strict?
        return compact! if should_compact?
        return false
      end

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

    def zero_mem_status(session_id: @session_id)
      raise ConfigurationError, "trace_store is not configured" unless @trace_store

      wm = @trace_store.get_watermark(@user_id, session_id)
      traces = @trace_store.list_traces(@user_id, session_id: session_id)
      last_seq = traces.map(&:sequence).max.to_i
      lag = [last_seq - wm[:last_sequence].to_i, 0].max
      {
        memory_mode: @memory_mode,
        session_id: session_id.to_s,
        trace_count: traces.size,
        last_sequence: last_seq,
        watermark_sequence: wm[:last_sequence].to_i,
        index_version: wm[:index_version].to_i,
        index_lag: lag
      }
    end

    def reindex_traces!(session_id: @session_id)
      raise ConfigurationError, "trace_store is not configured" unless @trace_store

      traces = @trace_store.list_traces(@user_id, session_id: session_id)
      traces.each do |trace|
        @trace_indexer.after_trace_write(trace: trace)
      end
      zero_mem_status(session_id: session_id)
    end

    def memory_mode
      @memory_mode
    end

    def zero_mem_enabled?
      ZeroMem::Mode.zero_mem_enabled?(@memory_mode)
    end

    def zero_mem_strict?
      ZeroMem::Mode.zero_mem_strict?(@memory_mode)
    end

    def hybrid?
      @memory_mode == :hybrid
    end

    def shadow_write_enabled?
      @memory_mode == :classic && Llmemory.configuration.zero_mem_shadow_write
    end

    def user_id
      @user_id
    end

    def llm_usage
      Llmemory::LLM::UsageLedger.new(store: @short_term_store).totals(@user_id)
    end

    def retrieve_fused(query, max_tokens: nil)
      raise ConfigurationError, "retrieve_fused requires memory_mode :hybrid" unless hybrid?
      raise ConfigurationError, "trace_store is not configured" unless @trace_store

      classic = @retrieval_engine.ranked_for(query, user_id: @user_id)
      evidence = zero_mem_engine.retrieve_evidence(query, max_tokens: max_tokens)
      skip_resources = evidence.profile&.workload_class != :procedural
      hybrid_fusion.fuse(
        classic_candidates: classic,
        evidence_set: evidence,
        max_tokens: max_tokens,
        skip_resources: skip_resources
      )
    end

    private

    def forget_log
      @forget_log ||= ForgetLog.new(store: @short_term_store)
    end

    def zero_mem_engine
      @zero_mem_engine ||= ZeroMem::Engine.new(trace_store: @trace_store, user_id: @user_id)
    end

    def trace_backed?
      !@trace_store.nil?
    end

    def compact_trace_deterministic!(max_bytes)
      msgs = messages
      current_bytes = messages_byte_size(msgs)
      return false if current_bytes <= max_bytes

      old_msgs, recent_msgs = split_messages_by_bytes(msgs, max_bytes)
      return false if old_msgs.empty?

      state = restore_state_for_save
      flush_ts = state[:last_flush_at] || state["last_flush_at"]
      save_state(messages: recent_msgs, last_compact_at: Time.now, last_flush_at: flush_ts)
      true
    end

    def append_message_to_checkpoint(role:, content:, occurred_at: nil, trace_id: nil)
      @short_term_store.update(@user_id, @session_id) do |state|
        state = normalize_state_hash(state)
        list = state[STATE_KEY_MESSAGES]
        list = list.is_a?(Array) ? list.dup : []
        entry = { role: role.to_sym, content: content.to_s }
        entry[:occurred_at] = occurred_at if occurred_at
        entry[:trace_id] = trace_id.to_s if trace_id
        list << entry
        list = sanitize_messages(list) if Llmemory.configuration.message_sanitizer_enabled
        state.merge(STATE_KEY_MESSAGES => list, last_activity_at: Time.now, **preserved_flush_state_from(state))
      end
    end

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
      tracked_llm_client
    end

    def tracked_llm_client
      @tracked_llm_client ||= Llmemory::LLM::TrackingClient.new(
        nil,
        user_id: @user_id,
        store: @short_term_store,
        api_key: @api_key
      )
    end

    def deny_generative!(operation)
      raise GenerativeOperationDisabled, "#{operation} is disabled when memory_mode is :zero_mem"
    end

    def generative_invoke_calls
      llm_usage.dig(:invoke, :calls).to_i
    end

    def generative_invoke_delta(before)
      generative_invoke_calls - before.to_i
    end

    def flush_memory_before_compaction!(msgs)
      return false if zero_mem_strict?
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
      preserved_flush_state_from(restore_state_for_save)
    end

    def preserved_flush_state_from(state)
      state = normalize_state_hash(state)
      {}.tap do |h|
        h[:last_flush_at] = state[:last_flush_at] if state[:last_flush_at]
        h[:last_compact_at] = state[:last_compact_at] if state[:last_compact_at]
      end
    end

    def normalize_state_hash(state)
      return {} unless state.is_a?(Hash)

      state.transform_keys(&:to_sym)
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
      llm_opts = { llm: tracked_llm_client, forget_log_store: @short_term_store }
      case long_term_type.to_s.to_sym
      when :graph_based
        LongTerm::GraphBased::Memory.new(
          user_id: @user_id,
          storage: LongTerm::GraphBased::Storages.build(cipher: @cipher),
          cipher: @cipher,
          **llm_opts
        )
      else
        LongTerm::FileBased::Memory.new(
          user_id: @user_id,
          storage: LongTerm::FileBased::Storages.build(cipher: @cipher),
          **llm_opts
        )
      end
    end

    def build_short_term_store(cipher)
      ShortTerm::Stores.build(cipher: cipher)
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
      ts = m[:occurred_at] || m["occurred_at"]
      if ts
        label = Llmemory::TimeCoercion.iso8601_or_string(ts)
        return "[#{label}] #{role}: #{content}"
      end

      "#{role}: #{content}"
    end

    def consolidation_reference_time(msgs)
      times = Array(msgs).filter_map do |m|
        Llmemory.parse_occurred_at(m[:occurred_at] || m["occurred_at"])
      end
      times.max
    end

    def consolidation_source_traces(msgs)
      Array(msgs).filter_map do |m|
        tid = m[:trace_id] || m["trace_id"]
        next if tid.to_s.strip.empty?

        {
          id: tid.to_s,
          content: (m[:content] || m["content"]).to_s
        }
      end
    end

    def consolidation_known_facts(conversation_text)
      return [] unless @long_term.respond_to?(:known_facts_for)

      @long_term.known_facts_for(conversation_text)
    end

    def combine_contexts(short_context, long_context)
      parts = []
      parts << short_context if short_context.to_s.strip.length.positive?
      parts << long_context.to_s.strip if long_context.to_s.strip.length.positive?
      parts.join("\n\n")
    end

    def retrieve_hybrid(query, short_context, max_tokens)
      fused = retrieve_fused(query, max_tokens: max_tokens)
      memory_context = fused.to_context
      combined = combine_contexts(short_context, memory_context)
      Llmemory::Instrumentation.instrument(
        :retrieve,
        query_chars: query.to_s.length,
        zero_mem_compliant: false,
        hybrid: true,
        fused: true,
        fact_count: fused.metrics[:fact_count],
        trace_count: fused.metrics[:trace_count],
        corroborated_count: fused.metrics[:corroborated_count]
      )
      combined
    end

    def hybrid_fusion
      @hybrid_fusion ||= Retrieval::HybridFusion.new
    end

    def count_context_tokens(text)
      (text.to_s.length / 4.0).ceil
    end

    def dedupe_hybrid_evidence(evidence_context, classic_context)
      classic_norm = classic_context.to_s.downcase
      evidence_context.to_s.lines.filter_map do |line|
        body = line.sub(/\A\[[^\]]+\]\s*/, "").strip.downcase
        next line if body.empty? || body.start_with?("===") || body.start_with?("Most relevant") || body.start_with?("Timeline")

        next nil if classic_norm.include?(body[0, [body.length, 80].min])

        line
      end.join("\n")
    end

    def split_trace_parts(content)
      max = Llmemory.configuration.max_message_chars.to_i
      text = content.to_s
      return [text] if max <= 0 || text.length <= max
      return [ZeroMem::Trace.normalize_content!(text)] if Llmemory.configuration.long_trace_strategy.to_sym == :raise

      text.chars.each_slice(max).map(&:join)
    end

    def message_batch_tokens(msgs)
      msgs.sum { |m| (format_message(m).length / 4.0).ceil }
    end

    def message_chunks(msgs, token_limit)
      chunks = []
      current = []
      current_tokens = 0
      msgs.each do |msg|
        t = (format_message(msg).length / 4.0).ceil
        if current.any? && current_tokens + t > token_limit
          chunks << current
          current = []
          current_tokens = 0
        end
        current << msg
        current_tokens += t
      end
      chunks << current if current.any?
      chunks
    end

    def split_hybrid_token_budget(max_tokens)
      return [nil, nil] if max_tokens.nil?

      ratio = Llmemory.configuration.hybrid_classic_token_ratio.to_f
      ratio = 0.5 unless ratio.positive? && ratio < 1.0
      classic = (max_tokens * ratio).to_i
      classic = 1 if classic < 1
      evidence = max_tokens - classic
      evidence = 1 if evidence < 1
      [evidence, classic]
    end
  end
end
