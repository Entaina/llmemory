# frozen_string_literal: true

module ZeroMemBenchmark
  # Interchangeable final reader. CI uses a deterministic stub (no HTTP).
  class Reader
    def initialize(client: nil)
      @client = client
    end

    def answer(question:, context:, gold_answer: nil)
      return @client.call(question: question, context: context, gold_answer: gold_answer) if @client

      DeterministicStub.answer(question: question, context: context, gold_answer: gold_answer)
    end

    module DeterministicStub
      module_function

      def answer(question:, context:, gold_answer: nil)
        ctx = context.to_s
        if gold_answer && ctx.downcase.include?(gold_answer.to_s.downcase.strip)
          return gold_answer.to_s
        end

        "UNKNOWN: #{question.to_s.strip[0, 80]}"
      end
    end
  end
end
