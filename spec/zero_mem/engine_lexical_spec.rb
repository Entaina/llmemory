# frozen_string_literal: true

RSpec.describe Llmemory::ZeroMem::Engine do
  let(:storage) { Llmemory::ZeroMem::Storages::Memory.new }
  let(:user_id) { "u_eng" }
  let(:session_id) { "s_eng" }

  it "rejects an llm keyword argument" do
    expect {
      described_class.new(trace_store: storage, user_id: user_id, llm: BombLLM.new)
    }.to raise_error(ArgumentError, /does not accept an llm/)
  end

  it "does not invoke generative LLM on long queries" do
    memory = Llmemory::Memory.new(user_id: user_id, session_id: session_id, trace_store: storage)
    memory.add_message(role: :user, content: "Project Atlas uses the Nimbus database for storage.")

    engine = described_class.new(trace_store: storage, user_id: user_id)
    long_query = "Necesito recordar todos los detalles del proyecto Atlas incluyendo la base de datos " \
                 "y cualquier referencia cruzada entre sesiones anteriores sobre Nimbus y despliegues."
    invoked = false
    bomb = Object.new
    bomb.define_singleton_method(:invoke) { |*_args| invoked = true }

    expect {
      engine.retrieve_evidence(long_query, top_k: 5)
    }.not_to raise_error
    expect(invoked).to be(false)
  end
end
