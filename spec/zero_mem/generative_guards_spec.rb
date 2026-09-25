# frozen_string_literal: true

RSpec.describe "generative retrieve stays local" do
  let(:trace_store) { Llmemory::ZeroMem::Storages::Memory.new }
  let(:memory) do
    Llmemory::Memory.new(
      user_id: "u_guard",
      session_id: "s1",
      trace_store: trace_store
    )
  end

  def invoke_calls
    memory.llm_usage.dig(:invoke, :calls).to_i
  end

  it "does not invoke the LLM on trace write or retrieve" do
    before = invoke_calls
    memory.add_message(role: :user, content: "Prefiero té verde.")
    memory.retrieve("té")
    memory.retrieve_evidence("té")
    expect(invoke_calls - before).to eq(0)
  end
end
