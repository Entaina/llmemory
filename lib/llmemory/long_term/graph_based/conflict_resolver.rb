# frozen_string_literal: true

require_relative "edge"

module Llmemory
  module LongTerm
    module GraphBased
      class ConflictResolver
        EXCLUSIVE_PREDICATES = %w[works_at lives_in current_job current_city employer residence].freeze

        def initialize(knowledge_graph)
          @graph = knowledge_graph
        end

        def resolve(new_edge)
          return [] unless exclusive_predicate?(new_edge.predicate)

          subject_id = new_edge.subject_id
          existing = @graph.find_edges(subject: subject_id, predicate: new_edge.predicate, include_archived: false)
          to_archive = existing.reject { |e| e.object_id == new_edge.object_id }
          to_archive.each do |e|
            @graph.archive_edge(e.id, reason: "replaced by #{new_edge.object_id}")
          end
          to_archive.map(&:id)
        end

        def exclusive_predicate?(predicate)
          EXCLUSIVE_PREDICATES.include?(predicate.to_s.downcase)
        end
      end
    end
  end
end
