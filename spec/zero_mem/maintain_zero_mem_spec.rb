# frozen_string_literal: true

RSpec.describe "maintain pass repairs traces" do
  let(:trace_store) { Llmemory::ZeroMem::Storages::Memory.new }
  let(:long_term) { double("LongTerm", memorize: true) }
  let(:memory) do
    Llmemory::Memory.new(
      user_id: "u_maint",
      session_id: "s1",
      trace_store: trace_store,
      long_term: long_term
    )
  end

  it "runs zero_mem repair after consolidate" do
    memory.add_message(role: :user, content: "hello")
    report = Llmemory::Maintenance::CognitivePass.run!(
      memory.user_id,
      memory: memory,
      reflect: false,
      mine_skills: false,
      expire: false
    )
    expect(report[:zero_mem]).not_to be_nil
    expect(report[:disabled]).not_to include(:consolidate)
  end
end
