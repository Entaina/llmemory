# frozen_string_literal: true

module Llmemory
  module ZeroMem
    class Evidence
      attr_reader :trace_id, :content, :role, :session_id, :occurred_at, :confidence, :score,
                  :sources, :conflict, :seed, :closure, :content_sha256

      def initialize(trace_id:, content:, role:, session_id:, occurred_at:, confidence:, score:,
                     sources: [], conflict: false, seed: true, closure: false, content_sha256: nil)
        @trace_id = trace_id
        @content = content
        @role = role
        @session_id = session_id
        @occurred_at = occurred_at
        @confidence = confidence.to_f
        @score = score.to_f
        @sources = Array(sources).map(&:to_sym).uniq
        @conflict = !!conflict
        @seed = !!seed
        @closure = !!closure
        @content_sha256 = content_sha256
      end

      def to_h
        {
          trace_id: trace_id,
          content: content,
          role: role,
          session_id: session_id,
          occurred_at: occurred_at.is_a?(Time) ? occurred_at.utc.iso8601(6) : occurred_at,
          confidence: confidence,
          score: score,
          sources: sources,
          conflict: conflict,
          seed: seed,
          closure: closure,
          content_sha256: content_sha256
        }
      end
    end
  end
end
