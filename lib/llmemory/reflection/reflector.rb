# frozen_string_literal: true

require "json"

module Llmemory
  module Reflection
    # Reflection distills an agent's recent episodes (episodic memory) into
    # durable, higher-order insights and writes them to semantic memory. This is
    # CoALA's "updating semantic memory with knowledge" (Reflexion / Generative
    # Agents): unlike one-shot extraction from raw text, it reasons over lived
    # experience to generalize lessons and patterns.
    #
    # Each insight is stored with provenance { method: "reflection",
    # sources: [{ type: "episode", id: ... }] } so it stays traceable to the
    # experiences that produced it.
    #
    # `semantic` must respond to:
    #   remember_fact(content:, category:, importance:, provenance:)
    # (FileBased::Memory implements this; graph-based is a future target.)
    class Reflector
      DEFAULT_CATEGORY = "insights"
      DEFAULT_IMPORTANCE = 0.6

      def initialize(episodic:, semantic:, llm: nil)
        @episodic = episodic
        @semantic = semantic
        @llm = llm || Llmemory::LLM.client
      end

      # Reflects over the most recent `window` episodes and writes the resulting
      # insights to semantic memory. Returns the ids of the stored insights.
      def reflect(window: 10, category: DEFAULT_CATEGORY)
        result = []
        Llmemory::Instrumentation.instrument(:reflect, window: window, category: category) do
          episodes = @episodic.recent_episodes(limit: window)
          next if episodes.empty?

          insights = distill(episodes)
          next if insights.empty?

          sources = episodes.map(&:id).compact.map { |id| { type: "episode", id: id } }

          result = insights.filter_map do |insight|
            provenance = Llmemory::Provenance.build(
              method: "reflection",
              sources: sources,
              confidence: insight[:confidence]
            )
            @semantic.remember_fact(
              content: insight[:content],
              category: category,
              importance: insight[:confidence] || DEFAULT_IMPORTANCE,
              provenance: provenance
            )
          end
        end
        result
      end

      private

      def distill(episodes)
        response = @llm.invoke(build_prompt(episodes))
        parse_insights(response)
      rescue Llmemory::LLMError
        []
      end

      def build_prompt(episodes)
        episodes_text = episodes.each_with_index.map do |ep, i|
          "Episode #{i + 1} (outcome: #{ep.outcome || 'n/a'}):\n#{ep.searchable_text}"
        end.join("\n\n")

        <<~PROMPT
          You are reflecting on an agent's recent experiences to distill durable,
          higher-order insights: lessons learned, recurring patterns, and stable
          preferences that will help in future situations. Generalize; do not
          restate raw events.

          Recent episodes:
          #{episodes_text}

          Return a JSON array of objects with "content" (the insight) and
          "confidence" (0-1) keys. Return an empty array if nothing durable can
          be concluded.
          Example: [{"content": "Rolling back on deploy failure reliably restores service", "confidence": 0.8}]
        PROMPT
      end

      def parse_insights(response)
        json = extract_json_array(response)
        return [] unless json

        json.filter_map do |item|
          next nil unless item.is_a?(Hash)
          content = item["content"] || item[:content]
          next nil if content.to_s.strip.empty?
          { content: content.to_s, confidence: normalize_confidence(item["confidence"] || item[:confidence]) }
        end
      end

      def normalize_confidence(value)
        return nil if value.nil?
        v = value.to_f
        v.between?(0, 1) ? v : nil
      end

      def extract_json_array(response)
        response = response.to_s.strip
        start_idx = response.index("[")
        end_idx = response.rindex("]")
        return nil unless start_idx && end_idx

        JSON.parse(response[start_idx..end_idx])
      rescue JSON::ParserError
        nil
      end
    end
  end
end
