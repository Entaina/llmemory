# frozen_string_literal: true

require "tmpdir"

RSpec.describe Llmemory::LongTerm::FileBased::Storages do
  describe ".build" do
    it "returns MemoryStorage when store is :memory" do
      storage = described_class.build(store: :memory)
      expect(storage).to be_a(Llmemory::LongTerm::FileBased::Storages::MemoryStorage)
    end

    it "returns FileStorage when store is :file" do
      storage = described_class.build(store: :file, base_path: Dir.mktmpdir)
      expect(storage).to be_a(Llmemory::LongTerm::FileBased::Storages::FileStorage)
    end

    it "returns DatabaseStorage when store is :postgres" do
      storage = described_class.build(store: :postgres, database_url: "postgres://localhost/test")
      expect(storage).to be_a(Llmemory::LongTerm::FileBased::Storages::DatabaseStorage)
    end

    it "returns ActiveRecordStorage when store is :active_record", skip: (defined?(ActiveRecord) ? false : "ActiveRecord not in bundle") do
      storage = described_class.build(store: :active_record)
      expect(storage).to be_a(Llmemory::LongTerm::FileBased::Storages::ActiveRecordStorage)
    end

    it "returns MemoryStorage when store is nil and config is default" do
      storage = described_class.build
      expect(storage).to be_a(Llmemory::LongTerm::FileBased::Storages::MemoryStorage)
    end
  end
end
