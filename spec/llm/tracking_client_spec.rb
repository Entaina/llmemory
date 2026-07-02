# frozen_string_literal: true

RSpec.describe Llmemory::LLM::TrackingClient do
  let(:store) { Llmemory::ShortTerm::Stores::MemoryStore.new }
  let(:inner) do
    Class.new do
      def invoke(_prompt)
        Llmemory::LLM::Response.new("ok", usage: Llmemory::LLM::Usage.new(input_tokens: 5, output_tokens: 2))
      end

      def invoke_with_json_schema(_prompt, _schema)
        { "entities" => [] }
      end

      def last_usage
        Llmemory::LLM::Usage.new(input_tokens: 5, output_tokens: 2, total_tokens: 7)
      end
    end.new
  end
  let(:client) { described_class.new(inner, user_id: "user_1", store: store) }
  let(:ledger) { Llmemory::LLM::UsageLedger.new(store: store) }

  before { Llmemory.reset_configuration! }

  it "delegates invoke and records usage" do
    response = client.invoke("hello")
    expect(response.to_s).to eq("ok")
    expect(ledger.totals("user_1")[:invoke][:total_tokens]).to eq(7)
    expect(ledger.totals("user_1")[:invoke][:calls]).to eq(1)
  end

  it "records usage after invoke_with_json_schema" do
    client.invoke_with_json_schema("hello", {})
    expect(ledger.totals("user_1")[:invoke][:calls]).to eq(1)
  end

  it "delegates last_usage to the inner client" do
    expect(client.last_usage.total_tokens).to eq(7)
  end
end
