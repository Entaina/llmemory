# frozen_string_literal: true

RSpec.describe "Zero-Mem generative guards" do
  let(:trace_store) { Llmemory::ZeroMem::Storages::Memory.new }
  let(:storage) { Llmemory::LongTerm::FileBased::Storages::MemoryStorage.new }
  let(:long_term) do
    Llmemory::LongTerm::FileBased::Memory.new(user_id: "u_guard", storage: storage, llm: BombLLM.new)
  end
  let(:memory) do
    Llmemory::Memory.new(
      user_id: "u_guard",
      session_id: "s1",
      trace_store: trace_store,
      long_term: long_term,
      memory_mode: :zero_mem
    )
  end

  def invoke_calls
    memory.llm_usage.dig(:invoke, :calls).to_i
  end

  it "does not invoke LLM on trace write, retrieve, compact, or maintain" do
    before = invoke_calls
    memory.add_message(role: :user, content: "Prefiero té verde.")
    memory.retrieve("té")
    memory.compact!(max_bytes: 100_000)
    report = Llmemory::Maintenance::CognitivePass.run!(memory.user_id, memory: memory, expire: false)
    expect(invoke_calls - before).to eq(0)
    expect(report[:disabled]).to include(:consolidate, :reflect, :mine)
  end

  it "raises GenerativeOperationDisabled on explicit generative ops" do
    memory.add_message(role: :user, content: "dato")
    expect { memory.consolidate! }.to raise_error(Llmemory::GenerativeOperationDisabled)
    expect { memory.reflect! }.to raise_error(Llmemory::GenerativeOperationDisabled)
    expect { memory.mine_skills! }.to raise_error(Llmemory::GenerativeOperationDisabled)
  end
end
