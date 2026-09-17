# frozen_string_literal: true

RSpec.describe Llmemory::TimeCoercion do
  it "parses ISO8601 strings" do
    t = described_class.parse_occurred_at("2023-05-08T12:00:00Z")
    expect(t.utc.iso8601).to eq("2023-05-08T12:00:00Z")
  end

  it "returns nil for unparseable values" do
    expect(described_class.parse_occurred_at("not a date")).to be_nil
  end
end
