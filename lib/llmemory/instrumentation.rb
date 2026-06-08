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
  #   llm_invoke.llmemory       provider:, model:, prompt_chars:, response_chars:
  #   llm_embed.llmemory        provider:, model:, text_chars:, dimensions:
  #   memory_write.llmemory     memory_type:, user_id:
  #   memory_forget.llmemory    memory_type:, user_id:, count:
  #   retrieve.llmemory         query_chars:, candidates:, results:
  #   iterative_retrieve.llmemory  hops:, total_results:
  #   reflect.llmemory          window:, insights:
  #   mine_skills.llmemory      window:, auto_register:
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
