# frozen_string_literal: true

RSpec.describe "Zero-Mem maintain pass" do
  let(:trace_store) { Llmemory::ZeroMem::Storages::Memory.new }
  let(:memory) do
    Llmemory::Memory.new(
      user_id: "u_maint",
      session_id: "s1",
      trace_store: trace_store,
      memory_mode: :zero_mem
    )
  end

  it "skips generative phases and runs zero_mem repair" do
    memory.add_message(role: :user, content: "hello")
    report = Llmemory::Maintenance::CognitivePass.run!(memory.user_id, memory: memory, expire: false)
    expect(report[:disabled]).to eq(%i[consolidate reflect mine])
    expect(report[:zero_mem]).not_to be_nil
    expect(report[:consolidated]).to be(false)
  end
end
