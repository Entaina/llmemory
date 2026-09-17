# frozen_string_literal: true

require "webmock/rspec"

RSpec.describe Llmemory::ZeroMem::Extractors::Http do
  let(:base) { "http://127.0.0.1:8765" }
  let(:extractor) { described_class.new(base_url: base) }

  it "calls /ner via HTTP without shell" do
    stub_request(:post, "#{base}/ner")
      .with(body: { text: "Hello Paris" }.to_json)
      .to_return(status: 200, body: { entities: [{ text: "Paris", normalized: "paris", type: "place", start: 6, end: 11 }] }.to_json)

    ents = extractor.extract("Hello Paris")
    expect(ents.first[:normalized]).to eq("paris")
  end

  it "surfaces HTTP errors" do
    stub_request(:post, "#{base}/ner").to_return(status: 500, body: "fail")
    expect { extractor.extract("x") }.to raise_error(Llmemory::StoreError, /sidecar HTTP/)
  end
end
