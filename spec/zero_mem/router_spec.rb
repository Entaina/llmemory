# frozen_string_literal: true

RSpec.describe Llmemory::ZeroMem::Router do
  let(:router) { described_class.new }

  def profile_for(text, boundary: nil)
    Llmemory::ZeroMem::QueryProfiler.new.profile(text, boundary: boundary)
  end

  it "routes multi-hop queries relationally in English" do
    profile = profile_for("What is the relationship between Atlas and Nimbus?")
    result = router.route(profile, hierarchy_scores: { "a" => 1.0 }, graph_scores: { "b" => 1.0 })
    expect(result[:route]).to eq(:relational)
    expect(result[:weights][:graph]).to eq(0.6)
  end

  it "routes temporal queries locally in Spanish" do
    profile = profile_for("¿Qué pasó después de la reserva?")
    result = router.route(profile, hierarchy_scores: { "a" => 1.0 }, graph_scores: { "b" => 1.0 })
    expect(result[:route]).to eq(:local)
    expect(result[:weights][:hierarchy]).to eq(0.6)
  end

  it "keeps explicit boundary on the profile without changing route table" do
    profile = profile_for("secret", boundary: { session_id: "s1" })
    expect(profile.boundary).to eq({ session_id: "s1" })
    result = router.route(profile, hierarchy_scores: {}, graph_scores: {})
    expect(result[:route]).to eq(:local)
  end
end
