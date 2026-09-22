# frozen_string_literal: true

RSpec.describe "Hybrid memory_mode retrieve" do
  let(:trace_store) { Llmemory::ZeroMem::Storages::Memory.new }
  let(:user_id) { "hybrid_user" }
  let(:storage) { Llmemory::LongTerm::FileBased::Storages::MemoryStorage.new }
  let(:llm_double) do
    double("LLM").tap do |d|
      allow(d).to receive(:invoke).and_return("[]")
      allow(d).to receive(:invoke).with(/Extract discrete facts/).and_return(
        '[{"content": "User owns a blue kayak named Nimbus"}]'
      )
      allow(d).to receive(:invoke).with(/Classify this fact/).and_return("personal_life")
      allow(d).to receive(:invoke).with(/Memory Synchronization Specialist/).and_return("# Profile\n")
    end
  end
  let(:long_term) do
    Llmemory::LongTerm::FileBased::Memory.new(user_id: user_id, storage: storage, llm: llm_double)
  end
  let(:retrieval_engine) do
    Llmemory::Retrieval::Engine.new(long_term, llm: llm_double)
  end

  before do
    Llmemory.reset_configuration!
  end

  def hybrid_memory
    Llmemory::Memory.new(
      user_id: user_id,
      session_id: "s1",
      trace_store: trace_store,
      memory_mode: :hybrid,
      long_term: long_term,
      retrieval_engine: retrieval_engine
    )
  end

  it "combines Zero-Mem evidence and classic long-term context after consolidate" do
    memory = hybrid_memory
    memory.add_message(role: :user, content: "I bought a blue kayak named Nimbus last week.")
    memory.consolidate!

    ctx = memory.retrieve("Nimbus kayak")
    expect(ctx).to include("=== MEMORY ===")
    expect(ctx).to match(/Nimbus|kayak/i)
    expect(storage.get_all_items(user_id).size).to be >= 1

    item = storage.get_all_items(user_id).first
    sources = (item[:provenance] || item["provenance"])[:sources] || (item[:provenance] || item["provenance"])["sources"]
    expect(sources.map { |s| s[:type] || s["type"] }).to include("trace")
  end

  it "retrieve_fused exposes ranked_trace_ids" do
    memory = hybrid_memory
    memory.add_message(role: :user, content: "Secret project Atlas database migration")
    fused = memory.retrieve_fused("Atlas database")
    expect(fused.ranked_trace_ids).not_to be_empty
  end

  it "routes strict zero_mem through evidence only" do
    Llmemory.configure { |c| c.memory_mode = :zero_mem }
    memory = Llmemory::Memory.new(
      user_id: user_id,
      session_id: "s1",
      trace_store: trace_store,
      long_term: long_term,
      retrieval_engine: retrieval_engine
    )
    memory.add_message(role: :user, content: "Atlas database migration project")

    expect { memory.consolidate! }.to raise_error(Llmemory::GenerativeOperationDisabled)

    ctx = memory.retrieve("Atlas database")
    expect(ctx).to include("ZERO-MEM EVIDENCE")
    expect(ctx).to include("Atlas")
  end

  it "keeps classic retrieve without Zero-Mem banner when mode is classic" do
    memory = Llmemory::Memory.new(
      user_id: user_id,
      session_id: "s1",
      long_term: long_term,
      retrieval_engine: retrieval_engine
    )
    memory.add_message(role: :user, content: "Secret code phrase: emerald-42")
    memory.consolidate!

    ctx = memory.retrieve("emerald")
    expect(ctx).not_to include("ZERO-MEM EVIDENCE")
    expect(ctx).to match(/emerald|Secret/i)
  end

  it "uses hybrid_classic_token_ratio as fact token ceiling in fused retrieve" do
    Llmemory.configure { |c| c.hybrid_classic_token_ratio = 0.5 }
    memory = hybrid_memory
    memory.add_message(role: :user, content: "The code phrase is emerald-42 for vault access.")
    memory.consolidate!
    fused = memory.retrieve_fused("emerald", max_tokens: 400)
    expect(fused.items).not_to be_empty
  end
end
