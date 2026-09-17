# frozen_string_literal: true

module Llmemory
  module ZeroMem
    class AnswerCalibrator
      def calibrate(answer, evidence_result:)
        answer = answer.to_s
        evidence = Array(evidence_result&.evidence)
        checks = []
        unsupported = []

        if list_like?(answer)
          checks << "list_answer"
          return unchanged(answer, checks, unsupported)
        end

        scalar = extract_scalar_candidate(answer)
        if scalar
          matches = evidence.select { |ev| ev.content.to_s.include?(scalar) }
          checks << "scalar_support"
          if matches.size == 1
            return {
              answer: scalar,
              changed: answer.strip != scalar,
              checks: checks,
              unsupported_fragments: unsupported
            }
          end

          checks << "ambiguous_scalar"
          return unchanged(answer, checks, unsupported)
        end

        checks << "free_text"
        unchanged(answer, checks, unsupported)
      end

      private

      def unchanged(answer, checks, unsupported)
        {
          answer: answer,
          changed: false,
          checks: checks,
          unsupported_fragments: unsupported
        }
      end

      def extract_scalar_candidate(answer)
        stripped = answer.strip
        return stripped if stripped.match?(/\A[\d.]+\z/)
        return stripped if stripped.length <= 32 && stripped !~ /\s/

        m = stripped.match(/\b([A-Z]{1,3})\b/)
        m&.[](1)
      end

      def list_like?(answer)
        answer.include?(",") || answer.match?(/\b(and|y)\b/i)
      end
    end
  end
end
