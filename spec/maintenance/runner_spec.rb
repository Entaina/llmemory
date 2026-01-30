# frozen_string_literal: true

RSpec.describe Llmemory::Maintenance::Runner do
  let(:storage) { Llmemory::LongTerm::FileBased::Storage.new }
  let(:user_id) { "user_1" }

  describe ".run_nightly" do
    it "returns true when storage is passed" do
      expect(described_class.run_nightly(user_id, storage: storage)).to be true
    end
  end

  describe ".run_weekly" do
    it "returns true when storage is passed" do
      expect(described_class.run_weekly(user_id, storage: storage)).to be true
    end
  end

  describe ".run_monthly" do
    it "returns true when storage is passed" do
      expect(described_class.run_monthly(user_id, storage: storage)).to be true
    end
  end
end
