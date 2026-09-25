# frozen_string_literal: true

RSpec.describe Llmemory::ZeroMem::HierarchyRetriever do
  let(:storage) { Llmemory::ZeroMem::Storages::Memory.new }
  let(:indexer) { Llmemory::ZeroMem::Indexer.new(storage) }
  let(:retriever) { described_class.new(storage) }
  let(:user_id) { "u_ret" }
  let(:session_id) { "s_ret" }

  before do
    memory = Llmemory::Memory.new(user_id: user_id, session_id: session_id, trace_store: storage)
    memory.add_message(role: :user, content: "My favorite color is teal.")
    memory.add_message(role: :assistant, content: "Noted teal.")
  end

  it "keeps the newest trace even when the query matches an older turn" do
    memory = Llmemory::Memory.new(user_id: "u_recent", session_id: "s_recent", trace_store: storage)
    memory.add_message(role: :user, content: "I love teal notebooks.", occurred_at: Time.utc(2023, 5, 1))
    memory.add_message(
      role: :user,
      content: "After learning to say no, I feel less stressed.",
      occurred_at: Time.utc(2023, 6, 1)
    )
    query = "I ended up volunteering and now I'm overwhelmed."
    profile = Llmemory::ZeroMem::QueryProfiler.new.profile(query)
    result = retriever.retrieve(user_id: "u_recent", query: query, profile: profile, top_k: 1)
    expect(result[:traces].map(&:content).join(" ")).to include("less stressed")
  end

  it "retrieves a long turn whose matching sentence sits after a long preamble" do
    memory = Llmemory::Memory.new(user_id: "u_long", session_id: "s_long", trace_store: storage)
    preamble = "The archive lists unrelated procurement notes and meeting logistics. " * 30
    memory.add_message(role: :assistant, content: "#{preamble}Model Boreal preserved numerical claims in the quarterly finance reports.")
    6.times do |i|
      memory.add_message(role: :user, content: "Choose a text summarization system soon, note #{i}.")
    end
    query = "Which text summarization system preserved numerical claims in the quarterly finance reports?"
    profile = Llmemory::ZeroMem::QueryProfiler.new.profile(query)
    result = retriever.retrieve(user_id: "u_long", query: query, profile: profile, top_k: 1)
    expect(result[:traces].map(&:content).join(" ")).to include("Boreal")
  end

  it "prefers a specific researching phrase over a generic research mention" do
    memory = Llmemory::Memory.new(user_id: "u_research", session_id: "s1", trace_store: storage)
    memory.add_message(
      role: :user,
      content: "Totally agree. Well, I'm off to go do some research.",
      occurred_at: Time.utc(2023, 5, 8)
    )
    memory2 = Llmemory::Memory.new(user_id: "u_research", session_id: "s2", trace_store: storage)
    memory2.add_message(
      role: :user,
      content: "Researching adoption agencies — it's been a dream to have a family.",
      occurred_at: Time.utc(2023, 5, 25)
    )
    query = "What did Caroline research?"
    profile = Llmemory::ZeroMem::QueryProfiler.new.profile(query)
    result = retriever.retrieve(user_id: "u_research", query: query, profile: profile, top_k: 3)
    joined = result[:traces].map(&:content).join(" ")
    expect(joined).to include("adoption agencies")
    expect(joined.index("adoption agencies")).to be < joined.index("go do some research")
  end

  it "returns traces with dense degradation flagged" do
    profile = Llmemory::ZeroMem::QueryProfiler.new.profile("favorite color teal")
    result = retriever.retrieve(user_id: user_id, query: "favorite color teal", profile: profile, top_k: 5)
    expect(result[:traces]).not_to be_empty
    expect(result[:degraded]).to include(:dense)
  end
end
