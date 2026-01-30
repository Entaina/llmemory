# frozen_string_literal: true

RSpec.describe Llmemory::Maintenance::Summarizer do
  let(:storage) { Llmemory::LongTerm::FileBased::Storage.new }
  let(:user_id) { "u1" }
  let(:llm_double) { double("LLM", invoke: "Summary of old memories.") }
  let(:summarizer) { described_class.new(storage, llm: llm_double) }

  before do
    storage.save_item(user_id, category: "work", content: "User works at X", source_resource_id: "r1")
    storage.save_category(user_id, "work", "")
  end

  it "run_weekly returns true" do
    expect(summarizer.run_weekly(user_id)).to be true
  end
end
