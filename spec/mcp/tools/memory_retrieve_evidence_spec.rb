# frozen_string_literal: true

require "json"
require "spec_helper"
require "llmemory/mcp"

RSpec.describe Llmemory::MCP::Tools::MemoryRetrieveEvidence do
  before do
    Llmemory.reset_configuration!
    Llmemory.configuration.short_term_store = :memory
    Llmemory.configuration.memory_mode = :zero_mem
    Llmemory::MCP::StoreHelpers.instance_variable_set(:@trace_store_instance, nil)
  end

  it "returns structured JSON with context text" do
    store = Llmemory::ZeroMem::Storages::Memory.new
    allow(Llmemory::ZeroMem::Storages).to receive(:build).and_return(store)

    memory = Llmemory::Memory.new(user_id: "u_ev", session_id: "default", trace_store: store, memory_mode: :zero_mem)
    memory.add_message(role: :user, content: "Project Atlas uses Nimbus")

    response = described_class.call(query: "Atlas database", user_id: "u_ev")
    expect(response).to be_a(::MCP::Tool::Response)
    payload = JSON.parse(response.content.first[:text])
    expect(payload["context"]).to be_a(String)
    expect(payload["evidence"]).to be_an(Array)
  end

  it "errors when memory_mode is classic" do
    Llmemory.configuration.memory_mode = :classic
    response = described_class.call(query: "x", user_id: "u")
    expect(response.instance_variable_get(:@error)).to be true
  end
end
