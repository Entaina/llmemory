# frozen_string_literal: true

module Llmemory
  # Lightweight instrumentation seam. When ActiveSupport::Notifications is
  # available (Rails apps, opt-in elsewhere), events are published with the
  # `.llmemory` suffix so subscribers can hook into LLM calls, retrieval,
  # writes and forgets for metrics, traces or cost dashboards. When AS is not
  # loaded, the block is yielded transparently and no event is emitted.
  #
  # Events (payload keys are best-effort; subscribers should treat them as
  # optional):
  #
  #   llm_invoke.llmemory       provider:, model:, prompt_chars:, response_chars:,
  #                             input_tokens:, output_tokens:, total_tokens:
  #   llm_embed.llmemory        provider:, model:, text_chars:, input_tokens:,
  #                             output_tokens:, total_tokens:
  #   memory_write.llmemory     memory_type:, user_id:
  #   memory_forget.llmemory    memory_type:, user_id:, count:
  #   retrieve.llmemory         query_chars:, candidates:, results:, zero_mem_compliant:
  #   iterative_retrieve.llmemory  hops:, total_results:
  #   reflect.llmemory          window:, insights:
  #   mine_skills.llmemory      window:, auto_register:
  #   trace_write.llmemory      user_id:, session_id:, trace_id:, sequence:, maintenance_fanout:
  #   zero_mem_state_update.llmemory  user_id:, state_key:, trace_id:, supersedes_trace_id:
  #   zero_mem_profile.llmemory       user_id:, query_chars:
  #   zero_mem_hierarchy_retrieve.llmemory  user_id:, workload:
  #   zero_mem_retrieve.llmemory      user_id:, evidence_count:, degraded:
  #   zero_mem_graph_retrieve.llmemory user_id:
  #   zero_mem_closure.llmemory       user_id:, seeds:
  #   zero_mem_calibrate.llmemory     user_id:, trace_count:
  #   encoder_embed.llmemory          user_id:, trace_id:, model:, dimensions:, duration_ms:
  module Instrumentation
    module_function

    def instrument(event, payload = {})
      name = "#{event}.llmemory"
      if defined?(ActiveSupport::Notifications)
        ActiveSupport::Notifications.instrument(name, payload) { yield if block_given? }
      else
        yield if block_given?
      end
    end
  end
end
