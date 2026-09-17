# frozen_string_literal: true

require "json"

module LocalBenchmark
  # LLM-as-judge using the same local model (not comparable to paper GPT-4o scores).
  class JudgeLLM
    def initialize(client: nil)
      @client = client
    end

    def correct?(question:, prediction:, reference:, task: nil)
      prompt = <<~PROMPT
        You are an evaluator. Decide if the prediction correctly answers the question given the reference answer.
        Reply with JSON only: {"correct": true} or {"correct": false}

        Task: #{task || "qa"}
        Question: #{question}
        Reference answer: #{reference}
        Prediction: #{prediction}
      PROMPT
      parse_bool(invoke(prompt))
    end

    def constraint_consistent?(question:, prediction:, constraints:)
      prompt = <<~PROMPT
        You evaluate constraint consistency for a personal assistant.
        The user had implicit constraints/preferences in past conversation (constraints).
        Given the question and assistant prediction, is the prediction consistent with those constraints?
        Reply JSON only: {"consistent": true} or {"consistent": false}

        Constraints:
        #{constraints}

        Question: #{question}
        Prediction: #{prediction}
      PROMPT
      parse_bool(invoke(prompt), key: "consistent")
    end

    def mem_syco_task(task_name:, question:, prediction:, reference:, memory_context:)
      prompt = <<~PROMPT
        MemSyco-Bench task: #{task_name}
        Decide if the prediction is appropriate given memory context and reference.
        Reply JSON only: {"correct": true} or {"correct": false}

        Memory context:
        #{memory_context.to_s[0, 8000]}

        Question: #{question}
        Reference: #{reference}
        Prediction: #{prediction}
      PROMPT
      parse_bool(invoke(prompt))
    end

    private

    def invoke(prompt)
      client = @client || Llmemory::LLM.client
      response = client.invoke(prompt)
      response.respond_to?(:content) ? response.content : response.to_s
    end

    def parse_bool(text, key: "correct")
      stripped = text.to_s.strip
      json = stripped[/\{.*\}/m]
      if json
        data = JSON.parse(json)
        return !!data[key] if data.key?(key)
        return !!data["correct"] if data.key?("correct")
      end
      stripped.match?(/\btrue\b/i)
    end
  end
end
