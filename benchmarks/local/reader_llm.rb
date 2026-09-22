# frozen_string_literal: true

require_relative "lm_studio"

module LocalBenchmark
  # Final QA reader backed by the configured LLM (LM Studio).
  class ReaderLLM
    ABSTAIN = "I don't know"

    def initialize(client: nil, mode: :qa)
      @client = client
      @mode = mode.to_sym
    end

    def call(question:, context:, gold_answer: nil, question_type: nil, **_extra)
      client = @client || Llmemory::LLM.client
      mode = question_type.to_s == "locomo_plus_continuation" ? :continuation : @mode
      prompt = build_prompt(question: question, context: context, mode: mode)
      response = if ENV["LLMEMORY_BENCH_TRACE"] == "1"
                   require_relative "bench_trace"
                   LocalBenchmark::BenchTrace.measure("reader_llm invoke (#{question.to_s[0, 40]})") do
                     client.invoke(prompt)
                   end
                 else
                   client.invoke(prompt)
                 end
      extract_content(response)
    end

    def to_reader
      ZeroMemBenchmark::Reader.new(client: method(:call))
    end

    private

    def build_prompt(question:, context:, mode: :qa)
      if mode == :continuation
        return <<~PROMPT
          Continue the speaker's message using ONLY the memory context below.
          The line to continue is the start of what they are saying now—write the rest in the same voice and tense.
          Do not repeat the prompt line. Output ONLY the continuation text (one or two sentences max).
          If the context lacks enough detail, reply with exactly: #{ABSTAIN}

          Memory:
          #{context.to_s.strip}

          Continue from: #{question.to_s.strip}

          Continuation:
        PROMPT
      end

      <<~PROMPT
        Answer the question using ONLY the context below.
        If the context does not contain enough information, reply with exactly: #{ABSTAIN}
        Do not invent facts or dates. Reply with ONLY the shortest answer (a phrase, value, or date)—no full sentences.
        For dates use the format "7 May 2023" when a specific day is known, or month/year when only that is known.
        Resolve relative phrases (last week, this month, last year) using explicit dates shown in brackets in the context.
        For questions about a person's identity, role, or what they researched, answer from explicit facts or dialogue in the context before #{ABSTAIN}.

        Context:
        #{context.to_s.strip}

        Question: #{question.to_s.strip}

        Answer:
      PROMPT
    end

    def extract_content(response)
      if response.respond_to?(:content)
        response.content.to_s.strip
      else
        response.to_s.strip
      end
    end
  end
end
