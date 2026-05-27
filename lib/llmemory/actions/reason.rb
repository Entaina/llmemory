# frozen_string_literal: true

module Llmemory
  module Actions
    # CoALA's "reasoning" action: read working memory, call the LLM, write the
    # result back to working memory. Unlike retrieval (long-term -> working) or
    # learning (working -> long-term), reasoning reads from and writes to working
    # memory, producing new information for the current decision.
    #
    # It is a small, composable primitive — agents can chain reason -> retrieve
    # -> reason — and deliberately does NOT touch long-term memory.
    #
    #   Llmemory::Actions::Reason.call(
    #     working_memory: wm,
    #     template: "Given goals {{goals}}, what is the next step?",
    #     into: :intermediate_reasoning
    #   )
    #
    # `template` is either a String (with {{slot}} placeholders filled from
    # working memory) or a callable that receives the WorkingMemory and returns
    # the prompt. `parse` optionally transforms the raw LLM output before it is
    # stored. `into` is the slot to write to (nil to reason without writing).
    # Returns the parsed result.
    class Reason
      DEFAULT_SLOT = :intermediate_reasoning

      def self.call(working_memory:, template:, into: DEFAULT_SLOT, parse: nil, llm: nil)
        client = llm || Llmemory::LLM.client
        prompt = render(template, working_memory)
        output = client.invoke(prompt).to_s
        result = parse ? parse.call(output) : output
        working_memory.set(into, result) unless into.nil?
        result
      end

      def self.render(template, working_memory)
        return template.call(working_memory).to_s if template.respond_to?(:call)
        interpolate(template.to_s, working_memory.to_h)
      end

      def self.interpolate(text, slots)
        text.gsub(/\{\{(\w+)\}\}/) do
          key = Regexp.last_match(1).to_sym
          slots.key?(key) ? slots[key].to_s : ""
        end
      end
    end
  end
end
