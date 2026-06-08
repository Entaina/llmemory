# frozen_string_literal: true

require "json"

module Llmemory
  module SkillMining
    # Skill mining scans an agent's recent episodes (episodic memory) for
    # repeated, successful trajectories and distills them into reusable skills
    # (procedural memory). This is Voyager's actual contribution: rather than a
    # passive, hand-written skill library, procedural memory grows from lived
    # experience.
    #
    # Mining is human-in-the-loop by default: `mine` returns skill *proposals*
    # and writes nothing. Pass `auto_register: true` to register them directly.
    # Each registered skill carries provenance { method: "skill_mining",
    # sources: [{ type: "episode", id: ... }] } so it stays traceable to the
    # experiences it was distilled from.
    #
    # `procedural` must respond to:
    #   register_skill(name:, body:, description:, kind:, provenance:)
    class Miner
      DEFAULT_WINDOW = 20
      DEFAULT_CONFIDENCE = 0.5
      VALID_KINDS = %w[prompt template code].freeze

      def initialize(episodic:, procedural:, llm: nil)
        @episodic = episodic
        @procedural = procedural
        @llm = llm || Llmemory::LLM.client
      end

      # Mines the most recent `window` episodes for reusable skills. When
      # `outcomes` (an allowlist of outcome labels) is given, only episodes whose
      # outcome is in the set are considered — a deterministic pre-filter.
      #
      # Returns an array of proposal hashes
      # ({ name:, kind:, body:, description:, confidence: }). When
      # `auto_register: true`, registers each proposal and returns the new skill
      # ids instead.
      def mine(window: DEFAULT_WINDOW, outcomes: nil, auto_register: false)
        result = []
        Llmemory::Instrumentation.instrument(:mine_skills, window: window, auto_register: auto_register) do
          episodes = @episodic.recent_episodes(limit: window)
          episodes = filter_by_outcome(episodes, outcomes) if outcomes
          next if episodes.empty?

          proposals = distill(episodes)
          next if proposals.empty?

          result = auto_register ? register(proposals, episodes) : proposals
        end
        result
      end

      private

      def filter_by_outcome(episodes, outcomes)
        allowed = Array(outcomes).map { |o| o.to_s.strip.downcase }
        episodes.select { |ep| allowed.include?(ep.outcome.to_s.strip.downcase) }
      end

      def register(proposals, episodes)
        sources = episodes.map(&:id).compact.map { |id| { type: "episode", id: id } }
        proposals.map do |p|
          provenance = Llmemory::Provenance.build(
            method: "skill_mining",
            sources: sources,
            confidence: p[:confidence]
          )
          @procedural.register_skill(
            name: p[:name],
            body: p[:body],
            description: p[:description],
            kind: p[:kind],
            provenance: provenance
          )
        end
      end

      def distill(episodes)
        response = @llm.invoke(build_prompt(episodes))
        parse_proposals(response)
      rescue Llmemory::LLMError
        []
      end

      def build_prompt(episodes)
        episodes_text = episodes.each_with_index.map do |ep, i|
          "Episode #{i + 1} (outcome: #{ep.outcome || 'n/a'}):\n#{ep.searchable_text}"
        end.join("\n\n")

        <<~PROMPT
          You are mining an agent's recent experiences for reusable skills. A skill
          is a repeatable procedure the agent can apply again: a prompt, a template,
          or a snippet of code. Only propose a skill when you see a SUCCESSFUL
          pattern that recurs across episodes — generalize the steps into a reusable
          procedure. Do not propose one-off actions or failures.

          Recent episodes:
          #{episodes_text}

          Return a JSON array of objects with keys:
            "name" (short snake_case identifier),
            "kind" (one of "prompt", "template", "code"),
            "body" (the reusable procedure itself),
            "description" (one sentence on when to apply it),
            "confidence" (0-1).
          Return an empty array if no reusable skill can be distilled.
          Example: [{"name": "rollback_on_deploy_failure", "kind": "prompt",
          "body": "When a deploy fails, roll back to the last known-good release.",
          "description": "Recover service after a failed deploy", "confidence": 0.8}]
        PROMPT
      end

      def parse_proposals(response)
        json = extract_json_array(response)
        return [] unless json

        json.filter_map do |item|
          next nil unless item.is_a?(Hash)
          name = (item["name"] || item[:name]).to_s.strip
          body = (item["body"] || item[:body]).to_s.strip
          next nil if name.empty? || body.empty?

          {
            name: name,
            kind: normalize_kind(item["kind"] || item[:kind]),
            body: body,
            description: presence(item["description"] || item[:description]),
            confidence: normalize_confidence(item["confidence"] || item[:confidence])
          }
        end
      end

      def normalize_kind(value)
        k = value.to_s.strip.downcase
        VALID_KINDS.include?(k) ? k : "prompt"
      end

      def normalize_confidence(value)
        return DEFAULT_CONFIDENCE if value.nil?
        v = value.to_f
        v.between?(0, 1) ? v : DEFAULT_CONFIDENCE
      end

      def presence(value)
        s = value.to_s.strip
        s.empty? ? nil : s
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
