# frozen_string_literal: true

RSpec.describe "Memory consolidation timestamps" do
  let(:user_id) { "timestamp_user" }
  let(:storage) { Llmemory::LongTerm::FileBased::Storages::MemoryStorage.new }
  let(:llm_double) do
    double("LLM").tap do |d|
      allow(d).to receive(:invoke).and_return("[]")
      allow(d).to receive(:invoke).with(/Extract discrete facts/).and_return('[{"content": "Went to a support group"}]')
      allow(d).to receive(:invoke).with(/Classify this fact/).and_return("personal_life")
      allow(d).to receive(:invoke).with(/Memory Synchronization Specialist/).and_return("# Profile\n")
    end
  end
  let(:long_term) do
    Llmemory::LongTerm::FileBased::Memory.new(user_id: user_id, storage: storage, llm: llm_double)
  end
  let(:memory) do
    Llmemory::Memory.new(
      user_id: user_id,
      session_id: "s1",
      long_term: long_term,
      retrieval_engine: Llmemory::Retrieval::Engine.new(long_term, llm: llm_double)
    )
  end

  it "stores occurred_at on checkpoint messages and passes reference_time to long-term storage" do
    anchor = Time.utc(2023, 5, 8, 12, 0, 0)
    memory.add_message(role: :user, content: "I went to a LGBTQ support group yesterday.", occurred_at: anchor)
    memory.consolidate!

    resource = storage.get_all_resources(user_id).first
    expect(resource[:text]).to include("Conversation anchor time")
    expect(resource[:text]).to include("2023-05-08")
    expect(resource[:created_at]).to eq(anchor)

    item = storage.get_all_items(user_id).first
    expect(item[:created_at]).to eq(anchor)
    expect(item[:provenance][:created_at]).to eq(anchor.utc.iso8601)
  end

  it "formats messages with timestamps for extraction" do
    memory.add_message(role: :user, content: "Hello", occurred_at: Time.utc(2024, 1, 2, 3, 4, 5))
    msgs = memory.messages
    expect(msgs.first[:occurred_at]).to eq(Time.utc(2024, 1, 2, 3, 4, 5))
  end
end
