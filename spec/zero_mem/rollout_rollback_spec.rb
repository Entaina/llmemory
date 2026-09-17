# frozen_string_literal: true

RSpec.describe "Zero-Mem rollout and rollback" do
  let(:trace_store) { Llmemory::ZeroMem::Storages::Memory.new }

  before do
    Llmemory.reset_configuration!
  end

  it "shadow-writes traces while keeping classic retrieve semantics" do
    Llmemory.configure { |c| c.zero_mem_shadow_write = true }
    memory = Llmemory::Memory.new(
      user_id: "u_roll",
      session_id: "s1",
      trace_store: trace_store,
      memory_mode: :classic
    )
    memory.add_message(role: :user, content: "shadow fact")
    expect(trace_store.list_traces("u_roll").size).to eq(1)

    context = memory.retrieve("shadow")
    expect(context).to include("shadow fact")
    expect(context).not_to include("ZERO-MEM EVIDENCE")
  end

  it "keeps traces after rollback to classic without trace reads" do
    Llmemory.configure { |c| c.zero_mem_shadow_write = true }
    memory = Llmemory::Memory.new(
      user_id: "u_rb",
      session_id: "s1",
      trace_store: trace_store,
      memory_mode: :classic
    )
    memory.add_message(role: :user, content: "persisted trace")
    trace_id = trace_store.list_traces("u_rb").first.id

    Llmemory.configure { |c| c.zero_mem_shadow_write = false }
    classic = Llmemory::Memory.new(
      user_id: "u_rb",
      session_id: "s1",
      trace_store: trace_store,
      memory_mode: :classic
    )
    expect(classic.trace_store.get_trace("u_rb", trace_id)).not_to be_nil
    expect do
      classic.retrieve_evidence("persisted")
    end.to raise_error(Llmemory::ConfigurationError, /zero_mem or :hybrid/)
  end
end
