# frozen_string_literal: true

require "json"

module Llmemory
  module Extractors
    class EntityRelationExtractor
      def initialize(llm: nil)
        @llm = llm || Llmemory::LLM.client
      end

      def extract(conversation_text)
        prompt = <<~PROMPT
          Extract entities and relations from this conversation as a knowledge graph.
          - Entities: people, companies, places, preferences, concepts (type and name).
          - Relations: subject-predicate-object triplets (e.g. User works_at OpenAI).
          Use "User" as subject when the user talks about themselves.
          Predicates: works_at, lives_in, prefers, is_allergic_to, likes, knows, current_job, current_city, etc.
          Return ONLY valid JSON with this shape:
          {"entities": [{"type": "person", "name": "User"}, {"type": "company", "name": "OpenAI"}], "relations": [{"subject": "User", "predicate": "works_at", "object": "OpenAI"}]}
          Conversation:
          #{conversation_text}
        PROMPT
        response = @llm.invoke(prompt.strip)
        parse_response(response)
      end

      private

      def parse_response(response)
        json = extract_json(response)
        return { entities: [], relations: [] } unless json.is_a?(Hash)
        entities = Array(json["entities"] || json[:entities]).map { |e| normalize_entity(e) }
        relations = Array(json["relations"] || json[:relations]).map { |r| normalize_relation(r) }
        { entities: entities, relations: relations }
      end

      def extract_json(response)
        response = response.to_s.strip
        start_idx = response.index("{")
        return nil unless start_idx
        depth = 0
        end_idx = nil
        response.each_char.with_index(start_idx) do |c, i|
          depth += 1 if c == "{"
          depth -= 1 if c == "}"
          if depth == 0
            end_idx = i
            break
          end
        end
        return nil unless end_idx
        JSON.parse(response[start_idx..end_idx])
      rescue JSON::ParserError
        nil
      end

      def normalize_entity(e)
        {
          type: (e["type"] || e[:type] || "concept").to_s.downcase,
          name: (e["name"] || e[:name]).to_s.strip
        }
      end

      def normalize_relation(r)
        {
          subject: (r["subject"] || r[:subject]).to_s.strip,
          predicate: (r["predicate"] || r[:predicate]).to_s.strip.downcase.gsub(/\s+/, "_"),
          object: (r["object"] || r[:object]).to_s.strip
        }
      end
    end
  end
end
