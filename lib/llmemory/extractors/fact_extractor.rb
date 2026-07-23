# frozen_string_literal: true

require "json"

module Llmemory
  module Extractors
    class FactExtractor
      def initialize(llm: nil)
        @llm = llm || Llmemory::LLM.client
      end

      def extract_items(conversation_text)
        prompt = <<~PROMPT
          Extract discrete facts from this conversation.
          Focus on preferences, behaviors, and important details.
          Conversation: #{conversation_text}
          Return as JSON array of objects with "content" and "importance" (0-1) keys.
          Importance: 0.8-0.95 for preferences/corrections/decisions, 0.5-0.8 for factual context, 0.3-0.5 for ephemeral.
          Example: [{"content": "User prefers Ruby", "importance": 0.9}, {"content": "User mentioned the weather", "importance": 0.4}]
        PROMPT
        response = @llm.invoke(prompt.strip)
        parse_items_response(response)
      end

      def evolve_summary(existing:, new_memories:)
        memory_list_text = Array(new_memories).map { |m| "- #{m}" }.join("\n")
        prompt = <<~PROMPT
          You are a Memory Synchronization Specialist.
          Topic Scope: User Profile

          ## Original Profile
          #{existing.to_s.empty? ? "No existing profile." : existing}

          ## New Memory Items to Integrate
          #{memory_list_text}

          # Task
          1. Update: If new items conflict with the Original Profile, overwrite the old facts.
          2. Add: If items are new, append them logically.
          3. Output: Return ONLY the updated markdown profile.
        PROMPT
        @llm.invoke(prompt.strip).to_s
      end

      def classify_item(content)
        classify_items([content])[content.to_s] || "general"
      end

      CLASSIFY_JSON_SCHEMA = {
        name: "fact_classification",
        schema: {
          type: "object",
          properties: {
            items: {
              type: "array",
              items: {
                type: "object",
                properties: {
                  content: { type: "string" },
                  category: { type: "string" }
                },
                required: ["content", "category"],
                additionalProperties: false
              }
            }
          },
          required: ["items"],
          additionalProperties: false
        }
      }.freeze

      def classify_items(contents)
        list = Array(contents).map(&:to_s).reject(&:empty?)
        return {} if list.empty?

        if @llm.respond_to?(:invoke_with_json_schema)
          begin
            numbered = list.map.with_index { |c, i| "#{i + 1}. #{c}" }.join("\n")
            prompt = <<~PROMPT
              Classify each fact into ONE category. Use lowercase with underscores.
              Examples: work_life, personal_life, preferences, general.

              Facts:
              #{numbered}

              Return one category per fact in the same order.
            PROMPT
            parsed = @llm.invoke_with_json_schema(prompt.strip, CLASSIFY_JSON_SCHEMA)
            mapped = map_classifications(parsed, list)
            return mapped if mapped.size == list.size
          rescue Llmemory::LLMError
            # fall back to per-item classification
          end
        end

        list.each_with_object({}) { |content, acc| acc[content] = classify_item_fallback(content) }
      end

      private

      def classify_item_fallback(content)
        return "general" if content.to_s.strip.empty?
        prompt = <<~PROMPT
          Classify this fact into ONE category. Use lowercase with underscores. Examples: work_life, personal_life, preferences, general.
          Fact: #{content}
          Return ONLY the category name, nothing else.
        PROMPT
        result = @llm.invoke(prompt.strip).to_s.strip.downcase.gsub(/\s+/, "_")
        result.empty? ? "general" : result
      end

      def map_classifications(parsed, contents)
        items = Array(parsed["items"] || parsed[:items])
        by_content = items.each_with_object({}) do |row, acc|
          content = (row["content"] || row[:content]).to_s
          category = (row["category"] || row[:category]).to_s.strip.downcase.gsub(/\s+/, "_")
          acc[content] = category.empty? ? "general" : category
        end
        contents.each_with_object({}) do |content, acc|
          acc[content] = by_content[content] || classify_item_fallback(content)
        end
      end

      def parse_items_response(response)
        json = extract_json_array(response)
        return [] unless json
        json.map do |item|
          h = item.is_a?(Hash) ? item : { "content" => item.to_s }
          imp = h["importance"] || h[:importance]
          h["importance"] = imp.nil? ? 0.7 : (imp.to_f.between?(0, 1) ? imp.to_f : 0.7)
          h
        end
      end

      def extract_json_array(response)
        response = response.to_s.strip
        start_idx = response.index("[")
        return nil unless start_idx
        end_idx = response.rindex("]")
        return nil unless end_idx
        JSON.parse(response[start_idx..end_idx])
      rescue JSON::ParserError
        nil
      end
    end
  end
end
