# frozen_string_literal: true

require "json"

module Llmemory
  module Extractors
    class EntityRelationExtractor
      # Long conversations often make the LLM return empty JSON; truncate for extraction.
      MAX_CONVERSATION_CHARS = 2500

      # JSON Schema for Structured Outputs (OpenAI response_format).
      # Ensures valid entities/relations shape and avoids refusals or malformed JSON.
      EXTRACTION_JSON_SCHEMA = {
        name: "entity_relation_extraction",
        schema: {
          type: "object",
          properties: {
            entities: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  type: { type: "string", description: "Entity type: person, company, place, concept, etc." },
                  name: { type: "string", description: "Entity name" }
                },
                required: ["type", "name"],
                additionalProperties: false
              },
              description: "List of entities mentioned in the conversation"
            },
            relations: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  subject: { type: "string", description: "Subject entity (use 'User' when the user talks about themselves or their family)" },
                  predicate: { type: "string", description: "Relation inferred from context, snake_case (e.g. has_son, works_at, likes, spouse)" },
                  object: { type: "string", description: "Object entity (person name, place, concept)" }
                },
                required: ["subject", "predicate", "object"],
                additionalProperties: false
              },
              description: "Subject-predicate-object relations extracted from the conversation"
            }
          },
          required: ["entities", "relations"],
          additionalProperties: false
        }
      }.freeze

      def initialize(llm: nil)
        @llm = llm || Llmemory::LLM.client
      end

      def extract(conversation_text)
        text = conversation_text.to_s.strip
        text = text[0, MAX_CONVERSATION_CHARS] + "\n[...]" if text.length > MAX_CONVERSATION_CHARS
        prompt = <<~PROMPT
          Infer entities and relations from this user-assistant conversation. Build a knowledge graph from what the user says, even when they don't state facts in formal language.
          - Entities: people, places, companies, concepts (type and name).
          - Relations: infer subject-predicate-object from context. Use "User" as subject when the user talks about themselves or people close to them.
          Examples of inference: "mi hijo se llama Luis" → User has_son Luis; "trabajo en Acme" → User works_at Acme; "no me gustan las macros" → User prefers (or dislikes) Excel macros. Infer family (has_son, has_daughter, spouse), work (works_at, current_job), preferences (likes, prefers), and any other relation that clearly follows from the conversation. Use snake_case predicates.
          Return empty arrays only if the conversation contains no extractable facts.

          Conversation:
          #{text}
        PROMPT

        result = extract_once(prompt.strip)
        # Retry with plain invoke() if API returned empty (avoids empty json_schema response)
        if (result[:entities].empty? && result[:relations].empty?) && text.length > 50
          result = parse_response(@llm.invoke(prompt.strip))
        end
        result
      end

      def extract_once(prompt)
        if @llm.respond_to?(:invoke_with_json_schema)
          begin
            parsed = @llm.invoke_with_json_schema(prompt, EXTRACTION_JSON_SCHEMA)
            if parsed.is_a?(Hash) && !parsed.empty?
              result = parse_response(parsed)
              return result if result[:entities].any? || result[:relations].any?
            end
          rescue Llmemory::LLMError
            # Model may not support response_format json_schema; fall back to invoke + parse
          end
        end

        response = @llm.invoke(prompt)
        parse_response(response)
      end

      private

      def parse_response(response)
        json = response.is_a?(Hash) ? response : extract_json(response)
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
