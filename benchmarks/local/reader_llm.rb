# frozen_string_literal: true

require_relative "lm_studio"

module LocalBenchmark
  # Final QA reader backed by the configured LLM (LM Studio).
  class ReaderLLM
    ABSTAIN = "I don't know"

    def initialize(client: nil)
      @client = client
    end

    def call(question:, context:, gold_answer: nil)
      client = @client || Llmemory::LLM.client
      prompt = build_prompt(question: question, context: context)
      response = client.invoke(prompt)
      extract_content(response)
    end

    def to_reader
      ZeroMemBenchmark::Reader.new(client: method(:call))
    end

    private

    def build_prompt(question:, context:)
      <<~PROMPT
        Answer the question using ONLY the context below.
        If the context does not contain enough information, reply with exactly: #{ABSTAIN}
        Do not invent facts. Keep the answer as short as possible (a phrase or sentence).

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
