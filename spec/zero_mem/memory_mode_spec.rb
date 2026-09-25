# frozen_string_literal: true

RSpec.describe "memory_mode" do
  before do
    Llmemory.reset_configuration!
  end

  it "always uses hybrid and builds a trace store" do
    memory = Llmemory::Memory.new(user_id: "u", session_id: "s1")
    expect(memory.memory_mode).to eq(:hybrid)
    expect(memory.trace_store).not_to be_nil
    expect(memory.hybrid?).to be(true)
    expect(memory.zero_mem_strict?).to be(false)
  end

  it "rejects classic and zero_mem" do
    expect do
      Llmemory.configure { |c| c.memory_mode = :classic }
    end.to raise_error(Llmemory::ConfigurationError, /invalid memory_mode/)

    expect do
      Llmemory::Memory.new(user_id: "u", memory_mode: :zero_mem)
    end.to raise_error(Llmemory::ConfigurationError, /invalid memory_mode/)
  end

  it "exposes retrieve_evidence" do
    memory = Llmemory::Memory.new(user_id: "u")
    memory.add_message(role: :user, content: "fact")
    expect(memory.retrieve_evidence("fact").evidence).not_to be_empty
  end
end
