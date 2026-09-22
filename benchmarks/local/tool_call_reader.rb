# frozen_string_literal: true

require "json"

module LocalBenchmark
  class ToolCallReader
    def initialize(client: nil)
      @client = client
    end

    def call(question:, context:, gold_answer: nil, metadata: nil)
      meta = metadata || {}
      schema = meta["tool_schema"] || meta[:tool_schema] || {}
      client = @client || Llmemory::LLM.client
      prompt = <<~PROMPT
        Select a tool and arguments to satisfy the user request using memory context.
        Reply with JSON only: {"name":"tool_name","arguments":{...}}

        Tool schema:
        #{JSON.pretty_generate(schema)}

        Memory context:
        #{context.to_s.strip}

        User request:
        #{question.to_s.strip}
      PROMPT
      response = client.invoke(prompt)
      text = response.respond_to?(:content) ? response.content : response.to_s
      text.to_s.strip
    end

    def to_reader_for_query(query)
      meta = query["metadata"] || {}
      reader = self
      ZeroMemBenchmark::Reader.new(
        client: lambda { |question:, context:, gold_answer: nil, **_kwargs|
          reader.call(question: question, context: context, gold_answer: gold_answer, metadata: meta)
        }
      )
    end
  end
end
