# frozen_string_literal: true

require "tmpdir"

RSpec.describe Llmemory::LongTerm::Episodic::Storages do
  describe ".build" do
    it "returns MemoryStorage when store is :memory" do
      expect(described_class.build(store: :memory)).to be_a(described_class::MemoryStorage)
    end

    it "returns FileStorage when store is :file" do
      expect(described_class.build(store: :file, base_path: Dir.mktmpdir)).to be_a(described_class::FileStorage)
    end

    it "returns DatabaseStorage when store is :postgres" do
      storage = described_class.build(store: :postgres, database_url: "postgres://localhost/test")
      expect(storage).to be_a(described_class::DatabaseStorage)
    end

    it "returns ActiveRecordStorage when store is :active_record", skip: (defined?(ActiveRecord) ? false : "ActiveRecord not in bundle") do
      expect(described_class.build(store: :active_record)).to be_a(described_class::ActiveRecordStorage)
    end

    it "defaults to MemoryStorage" do
      expect(described_class.build).to be_a(described_class::MemoryStorage)
    end
  end
end
