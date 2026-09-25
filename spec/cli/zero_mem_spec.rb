# frozen_string_literal: true

require "spec_helper"
require "llmemory/cli"

RSpec.describe "llmemory zero-mem CLI" do
  let(:trace_store) { Llmemory::ZeroMem::Storages::Memory.new }

  before do
    Llmemory.reset_configuration!
    allow(Llmemory::ZeroMem::Storages).to receive(:build).and_return(trace_store)
  end

  it "lists traces for a user" do
    memory = Llmemory::Memory.new(user_id: "u_cli", session_id: "default", trace_store: trace_store, memory_mode: :hybrid)
    memory.add_message(role: :user, content: "cli trace")

    output = capture_stdout do
      Llmemory::CLI.run(%w[zero-mem traces u_cli])
    end
    expect(output).to include("cli trace")
  end

  it "searches evidence without LLM" do
    memory = Llmemory::Memory.new(user_id: "u_cli", session_id: "default", trace_store: trace_store, memory_mode: :hybrid)
    memory.add_message(role: :user, content: "unique needle xyz")

    output = capture_stdout do
      Llmemory::CLI.run(%w[zero-mem search u_cli unique needle])
    end
    expect(output).to include("ZERO-MEM EVIDENCE")
    expect(output).to include("needle")
  end

  def capture_stdout
    previous = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = previous
  end
end
