# frozen_string_literal: true

RSpec.describe "Zero-Mem memory_mode" do
  let(:trace_store) { Llmemory::ZeroMem::Storages::Memory.new }

  before do
    Llmemory.reset_configuration!
  end

  it "defaults to hybrid with auto trace store" do
    memory = Llmemory::Memory.new(user_id: "u", session_id: "s1")
    expect(memory.memory_mode).to eq(:hybrid)
    expect(memory.trace_store).not_to be_nil
  end

  it "allows classic without auto trace store when configured" do
    Llmemory.configure { |c| c.memory_mode = :classic }
    memory = Llmemory::Memory.new(user_id: "u", session_id: "s1")
    expect(memory.memory_mode).to eq(:classic)
    expect(memory.trace_store).to be_nil
  end

  it "routes retrieve through Zero-Mem when mode is zero_mem" do
    Llmemory.configure { |c| c.memory_mode = :zero_mem }
    memory = Llmemory::Memory.new(user_id: "u", session_id: "s1", trace_store: trace_store)
    memory.add_message(role: :user, content: "Atlas database project")
    ctx = memory.retrieve("Atlas database")
    expect(ctx).to include("ZERO-MEM EVIDENCE")
  end

  it "exposes retrieve_evidence only in zero_mem modes" do
    classic = Llmemory::Memory.new(user_id: "u", trace_store: trace_store, memory_mode: :classic)
    expect do
      classic.retrieve_evidence("q")
    end.to raise_error(Llmemory::ConfigurationError, /zero_mem or :hybrid/)

    zm = Llmemory::Memory.new(user_id: "u", trace_store: trace_store, memory_mode: :zero_mem)
    zm.add_message(role: :user, content: "fact")
    expect(zm.retrieve_evidence("fact").evidence).not_to be_empty
  end
end
