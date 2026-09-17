# frozen_string_literal: true

RSpec.describe Llmemory::ZeroMem::QueryProfiler do
  let(:profiler) { described_class.new }

  it "detects temporal workload in Spanish" do
    profile = profiler.profile("¿A qué hora era la reserva de enero?")
    expect(profile.workload_class).to eq(:temporal)
    expect(profile.language).to eq(:es)
  end

  it "detects current_state in English" do
    profile = profiler.profile("What is the shipping address today?")
    expect(profile.workload_class).to eq(:current_state)
  end

  it "prefers explicit boundary over text inference" do
    profile = profiler.profile("anything", boundary: { session_id: "sess-x" })
    expect(profile.boundary[:session_id]).to eq("sess-x")
    expect(profile.rule_ids).to include("boundary_explicit")
  end
end
