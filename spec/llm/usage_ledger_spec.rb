# frozen_string_literal: true

RSpec.describe Llmemory::LLM::UsageLedger do
  let(:store) { Llmemory::ShortTerm::Stores::MemoryStore.new }
  let(:ledger) { described_class.new(store: store) }
  let(:usage) { Llmemory::LLM::Usage.new(input_tokens: 10, output_tokens: 5, total_tokens: 15) }
  let(:embed_usage) { Llmemory::LLM::Usage.new(input_tokens: 0, output_tokens: 0, total_tokens: 4) }

  before { Llmemory.reset_configuration! }

  describe "#record and #totals" do
    it "accumulates invoke and embed usage per user" do
      ledger.record("user_1", usage, operation: :invoke)
      ledger.record("user_1", embed_usage, operation: :embed)
      ledger.record("user_1", usage, operation: :invoke)

      totals = ledger.totals("user_1")
      expect(totals[:invoke][:input_tokens]).to eq(20)
      expect(totals[:invoke][:output_tokens]).to eq(10)
      expect(totals[:invoke][:total_tokens]).to eq(30)
      expect(totals[:invoke][:calls]).to eq(2)
      expect(totals[:embed][:total_tokens]).to eq(4)
      expect(totals[:embed][:calls]).to eq(1)
      expect(totals[:updated_at]).not_to be_nil
    end

    it "isolates usage by user" do
      ledger.record("user_a", usage, operation: :invoke)
      expect(ledger.totals("user_b")[:invoke][:calls]).to eq(0)
    end
  end

  describe "#reset!" do
    it "clears stored totals" do
      ledger.record("user_1", usage, operation: :invoke)
      ledger.reset!("user_1")
      totals = ledger.totals("user_1")
      expect(totals[:invoke][:calls]).to eq(0)
      expect(totals[:embed][:calls]).to eq(0)
    end
  end

  describe ".format_text" do
    it "formats totals for display" do
      ledger.record("user_1", usage, operation: :invoke)
      text = described_class.format_text(ledger.totals("user_1"))
      expect(text).to include("LLM TOKEN USAGE")
      expect(text).to include("15 total")
      expect(text).to include("1 calls")
    end
  end
end
