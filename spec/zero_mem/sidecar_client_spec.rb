# frozen_string_literal: true

require "webmock/rspec"

RSpec.describe Llmemory::ZeroMem::SidecarClient do
  let(:base_url) { "http://127.0.0.1:8765" }

  it "opens the circuit after repeated failures" do
    stub_request(:post, "#{base_url}/ner").to_return(status: 500, body: "err")
    client = described_class.new(base_url: base_url, timeout: 1, breaker: Llmemory::ZeroMem::CircuitBreaker.new(failure_threshold: 2))

    2.times do
      expect { client.post_json("/ner", { text: "hello" }) }.to raise_error(Llmemory::StoreError)
    end
    expect(client.degraded?).to be(true)
    expect { client.post_json("/ner", { text: "hello" }) }.to raise_error(Llmemory::StoreError, /circuit open/)
  end

  it "returns parsed entities on success" do
    stub_request(:post, "#{base_url}/ner")
      .to_return(status: 200, body: { entities: [{ text: "Atlas", normalized: "atlas", start: 0, end: 5 }] }.to_json)
    client = described_class.new(base_url: base_url, timeout: 1)
    body = client.post_json("/ner", { text: "Atlas" })
    expect(body["entities"].first["text"]).to eq("Atlas")
  end
end
