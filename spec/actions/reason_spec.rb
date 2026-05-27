# frozen_string_literal: true

RSpec.describe Llmemory::Actions::Reason do
  let(:store) { Llmemory::ShortTerm::Stores::MemoryStore.new }
  let(:wm) { Llmemory::WorkingMemory.new(user_id: "u1", session_id: "s1", store: store) }

  def llm_returning(value)
    double("LLM").tap { |d| allow(d).to receive(:invoke).and_return(value) }
  end

  # Captures the prompt the LLM was invoked with, and echoes a fixed answer.
  def llm_capturing(sink)
    double("LLM").tap do |d|
      allow(d).to receive(:invoke) do |prompt|
        sink << prompt
        "the answer"
      end
    end
  end

  it "writes the LLM output into intermediate_reasoning by default" do
    described_class.call(working_memory: wm, template: "Think about it", llm: llm_returning("a deduction"))
    expect(wm.intermediate_reasoning).to eq("a deduction")
  end

  it "interpolates {{slot}} placeholders from working memory into the prompt" do
    wm.goals = ["ship P7"]
    wm.current_task = "write reason action"
    prompts = []
    described_class.call(
      working_memory: wm,
      template: "Goals: {{goals}}. Task: {{current_task}}. Next?",
      llm: llm_capturing(prompts)
    )
    expect(prompts.first).to include("ship P7", "write reason action")
  end

  it "leaves unknown placeholders blank" do
    prompts = []
    described_class.call(working_memory: wm, template: "X={{nonexistent}}!", llm: llm_capturing(prompts))
    expect(prompts.first).to eq("X=!")
  end

  it "accepts a callable template receiving the working memory" do
    wm.current_task = "deploy"
    prompts = []
    template = ->(working_memory) { "Task is #{working_memory.current_task}" }
    described_class.call(working_memory: wm, template: template, llm: llm_capturing(prompts))
    expect(prompts.first).to eq("Task is deploy")
  end

  it "writes into a custom slot" do
    described_class.call(working_memory: wm, template: "t", into: :scratchpad, llm: llm_returning("note"))
    expect(wm.scratchpad).to eq("note")
    expect(wm.intermediate_reasoning).to be_nil
  end

  it "applies a parse callable before storing and returning" do
    result = described_class.call(
      working_memory: wm,
      template: "list",
      parse: ->(out) { out.split(",").map(&:strip) },
      llm: llm_returning("a, b, c")
    )
    expect(result).to eq(%w[a b c])
    expect(wm.intermediate_reasoning).to eq(%w[a b c])
  end

  it "does not write when into is nil but still returns the result" do
    result = described_class.call(working_memory: wm, template: "t", into: nil, llm: llm_returning("ephemeral"))
    expect(result).to eq("ephemeral")
    expect(wm.to_h).to eq({})
  end

  it "supports composing reason -> reason via working memory" do
    wm.last_observation = "tests failing"
    described_class.call(
      working_memory: wm,
      template: "Observation: {{last_observation}}. Diagnose.",
      into: :intermediate_reasoning,
      llm: llm_returning("flaky setup")
    )
    prompts = []
    described_class.call(
      working_memory: wm,
      template: "Given diagnosis {{intermediate_reasoning}}, propose a fix.",
      into: :scratchpad,
      llm: llm_capturing(prompts)
    )
    expect(prompts.first).to include("flaky setup")
    expect(wm.scratchpad).to eq("the answer")
  end
end
