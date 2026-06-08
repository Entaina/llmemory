# frozen_string_literal: true

module Llmemory
  module MCP
    module Tools
      class MemoryMineSkills < ::MCP::Tool
        description "Mine reusable skills from a user's successful episode trajectories (procedural learning). Human-in-the-loop by default: returns skill *proposals* and writes nothing. Set auto_register=true to register them in procedural memory (with provenance back to the source episodes)."

        input_schema(
          properties: {
            user_id: { type: "string", description: "User identifier" },
            window: { type: "integer", description: "Episodes to mine (default 20)" },
            outcomes: { type: "array", items: { type: "string" }, description: "Optional allowlist of outcome labels to pre-filter episodes (e.g. ['success'])" },
            auto_register: { type: "boolean", description: "Register the proposals instead of only returning them (default false)" }
          },
          required: ["user_id"]
        )

        class << self
          def call(user_id:, window: nil, outcomes: nil, auto_register: false, server_context: nil)
            episodic = Llmemory::LongTerm::Episodic::Memory.new(user_id: user_id)
            procedural = Llmemory::LongTerm::Procedural::Memory.new(user_id: user_id)
            result = Llmemory::SkillMining::Miner.new(episodic: episodic, procedural: procedural).mine(
              window: (window || Llmemory::SkillMining::Miner::DEFAULT_WINDOW).to_i,
              outcomes: outcomes,
              auto_register: auto_register
            )

            ::MCP::Tool::Response.new([{ type: "text", text: format_result(user_id, result, auto_register) }])
          rescue => e
            ::MCP::Tool::Response.new([{ type: "text", text: "Error mining skills: #{e.message}" }], error: true)
          end

          private

          def format_result(user_id, result, auto_register)
            return "No skills could be mined for user #{user_id}." if result.empty?

            if auto_register
              "Registered #{result.size} mined skill(s): #{result.join(', ')}"
            else
              lines = ["#{result.size} skill proposal(s) for user #{user_id} (not registered):"]
              result.each do |p|
                lines << "  - #{p[:name]} (#{p[:kind]}, confidence: #{p[:confidence]}): #{p[:description] || p[:body]}"
              end
              lines.join("\n")
            end
          end
        end
      end
    end
  end
end
