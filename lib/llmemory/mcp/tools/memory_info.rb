# frozen_string_literal: true

module Llmemory
  module MCP
    module Tools
      class MemoryInfo < ::MCP::Tool
        description "Get documentation on how to use llmemory tools effectively. Read this first to understand the memory system."

        input_schema(
          properties: {}
        )

        class << self
          def call(server_context: nil)
            ::MCP::Tool::Response.new([{
              type: "text",
              text: documentation_text
            }])
          end

          private

          def documentation_text
            <<~DOC
              # llmemory - Memory System for LLM Agents

              ## Overview
              llmemory provides persistent memory across conversations, combining:
              - **Short-term memory**: Recent conversation messages per session
              - **Long-term memory**: Extracted facts, preferences, and observations

              ## Recommended Workflow

              ### 1. Start of Conversation
              Use memory_retrieve to get relevant context:
              ```
              memory_retrieve(query: "<user's first message>", user_id: "user123")
              ```
              This returns relevant context from both short and long-term memory.

              ### 2. During Conversation
              Save important observations as you learn them:
              ```
              memory_save(user_id: "user123", content: "User prefers concise answers")
              ```

              ### 3. End of Conversation
              Consolidate the conversation to extract and store facts:
              ```
              memory_consolidate(user_id: "user123", session_id: "default")
              ```

              ## Tools Reference

              | Tool | Purpose |
              |------|---------|
              | memory_search | Find specific memories by query |
              | memory_save | Store a new observation/fact |
              | memory_retrieve | Get context for LLM inference |
              | memory_timeline | Get recent memories chronologically |
              | memory_timeline_context | Get N items before/after a specific memory |
              | memory_add_message | Add message to short-term |
              | memory_consolidate | Extract facts from conversation |
              | memory_stats | Get memory statistics |

              ## Best Practices

              1. **Be specific** when saving observations
              2. **Use categories** to organize facts (preferences, work, personal, technical)
              3. **Consolidate regularly** to not lose important information
              4. **Search before asking** - check if you already know something
              5. **Use session_id** to separate different conversation contexts
            DOC
          end
        end
      end
    end
  end
end
