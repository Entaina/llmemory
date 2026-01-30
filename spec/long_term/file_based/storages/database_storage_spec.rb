# frozen_string_literal: true

RSpec.describe Llmemory::LongTerm::FileBased::Storages::DatabaseStorage do
  let(:user_id) { "user_1" }

  it "requires database_url to connect" do
    storage = described_class.new(database_url: nil)
    allow(Llmemory.configuration).to receive(:database_url).and_return(nil)
    expect { storage.save_resource(user_id, "text") }.to raise_error(StandardError)
  end

  it "is built by Storages.build with store :postgres" do
    storage = Llmemory::LongTerm::FileBased::Storages.build(store: :postgres, database_url: "postgres://localhost/test_db")
    expect(storage).to be_a(described_class)
  end
end
