# frozen_string_literal: true

require "json"
require_relative "../store_helpers"

module Llmemory
  module MCP
    module Tools
      class MemoryRetrieveEvidence < ::MCP::Tool
        description "Retrieve structured Zero-Mem evidence (traces) for a query without generative LLM calls. Returns JSON plus a text context block."

        input_schema(
          properties: {
            query: { type: "string", description: "Evidence query" },
            user_id: { type: "string", description: "User identifier" },
            session_id: { type: "string", description: "Session identifier (default: 'default')" },
            top_k: { type: "integer", description: "Maximum seed traces (default from config)" },
            max_tokens: { type: "integer", description: "Token budget for assembled evidence" },
            boundary: { type: "object", description: "Optional session/boundary filter" },
            explain: { type: "boolean", description: "Include routing/fusion explain payload (default false)" }
          },
          required: ["query", "user_id"]
        )

        class << self
          def call(query:, user_id:, session_id: nil, top_k: nil, max_tokens: nil, boundary: nil,
                   explain: false, server_context: nil)
            unless ZeroMem::Mode.zero_mem_enabled?(Llmemory.configuration.memory_mode)
              return error_response("memory_retrieve_evidence requires memory_mode :zero_mem or :hybrid")
            end

            session = session_id || "default"
            memory = StoreHelpers.build_memory(user_id: user_id, session_id: session)
            result = memory.retrieve_evidence(
              query,
              top_k: top_k,
              max_tokens: max_tokens,
              boundary: boundary,
              explain: explain == true
            )

            payload = {
              route: result.route,
              profile: result.profile.to_h,
              evidence: result.evidence.map(&:to_h),
              seed_evidence: result.seed_evidence.map(&:to_h),
              closure_evidence: result.closure_evidence.map(&:to_h),
              metrics: result.metrics,
              degraded: result.degraded,
              warnings: result.warnings,
              explain: result.explain,
              context: result.to_context
            }

            ::MCP::Tool::Response.new([{
              type: "text",
              text: JSON.pretty_generate(payload)
            }])
          rescue => e
            error_response(e.message)
          end

          def error_response(message)
            ::MCP::Tool::Response.new([{ type: "text", text: "Error retrieving evidence: #{message}" }], error: true)
          end
        end
      end
    end
  end
end
