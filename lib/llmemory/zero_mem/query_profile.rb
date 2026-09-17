# frozen_string_literal: true

module Llmemory
  module ZeroMem
    class QueryProfile
      ANSWER_TYPES = %i[person place datetime number duration boolean list free_text].freeze
      WORKLOADS = %i[local_fact cross_session temporal current_state multi_hop procedural].freeze

      attr_reader :subject_entities, :keywords, :quoted_phrases, :answer_type, :temporal_cues,
                  :aggregation_cues, :boundary, :workload_class, :freshness_requirement,
                  :expected_evidence_count, :language, :rule_ids

      def initialize(subject_entities:, keywords:, quoted_phrases:, answer_type:, temporal_cues:,
                     aggregation_cues:, boundary:, workload_class:, freshness_requirement:,
                     expected_evidence_count:, language:, rule_ids:)
        @subject_entities = subject_entities
        @keywords = keywords
        @quoted_phrases = quoted_phrases
        @answer_type = answer_type
        @temporal_cues = temporal_cues
        @aggregation_cues = aggregation_cues
        @boundary = boundary
        @workload_class = workload_class
        @freshness_requirement = freshness_requirement
        @expected_evidence_count = expected_evidence_count
        @language = language
        @rule_ids = rule_ids
      end

      def to_h
        {
          subject_entities: subject_entities,
          keywords: keywords,
          quoted_phrases: quoted_phrases,
          answer_type: answer_type,
          temporal_cues: temporal_cues,
          aggregation_cues: aggregation_cues,
          boundary: boundary,
          workload_class: workload_class,
          freshness_requirement: freshness_requirement,
          expected_evidence_count: expected_evidence_count,
          language: language,
          rule_ids: rule_ids
        }
      end
    end
  end
end
