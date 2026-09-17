# frozen_string_literal: true

RSpec.describe Llmemory::ZeroMem::GraphRetriever do
  let(:storage) { Llmemory::ZeroMem::Storages::Memory.new }
  let(:retriever) { described_class.new(storage) }
  let(:user_id) { "u_graph" }
  let(:session_id) { "s1" }

  def write(content, seq)
    trace = Llmemory::ZeroMem::Trace.build(
      user_id: user_id,
      session_id: session_id,
      role: :user,
      content: content,
      sequence: seq
    )
    storage.write_trace(trace)
    Llmemory::ZeroMem::EntityIndex.new(storage).index_trace(trace)
    trace
  end

  it "retrieves two-hop related traces without LLM" do
    t1 = write("Project Atlas uses the Nimbus database.", 1)
    write("Unrelated filler about lunch plans.", 2)
    t3 = write("Atlas backups run on Nimbus nightly.", 3)

    profile = Llmemory::ZeroMem::QueryProfiler.new.profile("Which database does Atlas use?")
    result = retriever.retrieve(user_id: user_id, query: "Which database does Atlas use?", profile: profile, top_k: 5)
    ids = result[:traces].map(&:id)
    expect(ids).to include(t1.id, t3.id)
    expect(result[:degraded]).to include(:dense)
  end
end
