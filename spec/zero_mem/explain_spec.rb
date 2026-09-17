# frozen_string_literal: true

RSpec.describe "Zero-Mem explain payload" do
  let(:storage) { Llmemory::ZeroMem::Storages::Memory.new }

  it "includes thresholds and a reason for each exclusion" do
    memory = Llmemory::Memory.new(user_id: "u_explain", session_id: "s1", trace_store: storage)
    memory.record_trace(role: :user, content: "visible fact", add_to_checkpoint: false)
    archived = Llmemory::ZeroMem::Trace.build(
      user_id: "u_explain",
      session_id: "s1",
      role: :user,
      content: "hidden",
      sequence: 99
    )
    storage.write_trace(archived)
    storage.archive_trace("u_explain", archived.id)

    engine = Llmemory::ZeroMem::Engine.new(trace_store: storage, user_id: "u_explain")
    result = engine.retrieve_evidence(
      "visible fact",
      explain: true,
      skip_closure: true,
      current_trace_id: nil
    )

    expect(result.explain[:thresholds]).to include(:rho, :gamma, :top_k)
    expect(result.explain[:fusion][:per_trace]).not_to be_empty
  end
end
