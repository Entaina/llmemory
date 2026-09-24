# frozen_string_literal: true

RSpec.describe Llmemory::ZeroMem::QueryProfiler do
  let(:profiler) { described_class.new }

  it "detects temporal workload in Spanish" do
    profile = profiler.profile("¿A qué hora era la reserva de enero?")
    expect(profile.workload_class).to eq(:temporal)
    expect(profile.language).to eq(:es)
  end

  it "treats deadline questions as temporal even when they start with what is" do
    profile = profiler.profile("What is the deadline for Reporting to validate the ESG policy? (YYYY-MM-DD)")
    expect(profile.workload_class).to eq(:temporal)
    expect(profile.temporal_cues.join(" ")).to match(/deadline/i)
  end

  it "detects current_state in English" do
    profile = profiler.profile("What is the shipping address today?")
    expect(profile.workload_class).to eq(:current_state)
  end

  it "counts across months without treating the months as entities" do
    profile = profiler.profile(
      "How many times did I ride rollercoasters across all the events I attended from July to October?"
    )
    expect(profile.subject_entities).not_to include("July", "October", "How")
    expect(profile.workload_class).to eq(:temporal)
    expect(profile.answer_type).to eq(:number)
    expect(profile.expected_evidence_count).to eq(Llmemory.configuration.zero_mem_max_top_k)
  end

  it "treats a who-question as a person answer about the named subject" do
    profile = profiler.profile("Who was the Norse leader?")
    expect(profile.answer_type).to eq(:person)
    expect(profile.subject_entities).to eq(["Norse"])
  end

  it "does not treat a leading When as a second entity" do
    profile = profiler.profile("When is Melanie planning on going camping?")
    expect(profile.subject_entities).to eq(["Melanie"])
    expect(profile.workload_class).to eq(:temporal)
  end

  it "classifies identity or research questions as local_fact" do
    profile = profiler.profile("What did Caroline research?")
    expect(profile.workload_class).to eq(:local_fact)
    expect(profile.rule_ids).to include("attribute_fact_cue")
  end

  it "prefers explicit boundary over text inference" do
    profile = profiler.profile("anything", boundary: { session_id: "sess-x" })
    expect(profile.boundary[:session_id]).to eq("sess-x")
    expect(profile.rule_ids).to include("boundary_explicit")
  end
end
