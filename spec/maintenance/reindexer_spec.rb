# frozen_string_literal: true

RSpec.describe Llmemory::Maintenance::Reindexer do
  let(:storage) { Llmemory::LongTerm::FileBased::Storage.new }
  let(:user_id) { "u1" }
  let(:reindexer) { described_class.new(storage) }

  before do
    storage.save_item(user_id, category: "general", content: "Old", source_resource_id: "r1")
    storage.save_resource(user_id, "Old resource")
  end

  it "run_monthly returns true" do
    expect(reindexer.run_monthly(user_id)).to be true
  end
end
