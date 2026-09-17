# frozen_string_literal: true

require "webmock/rspec"
require File.expand_path("../../../benchmarks/local/lm_studio", __dir__)
require File.expand_path("../../../benchmarks/local/reader_llm", __dir__)

RSpec.describe LocalBenchmark::LmStudio do
  describe ".health_check!" do
    it "passes when expected model is loaded" do
      stub_request(:get, "http://127.0.0.1:1234/v1/models")
        .to_return(status: 200, body: { data: [{ id: "qwen2.5-7b-instruct" }] }.to_json)

      Llmemory.configure do |c|
        c.llm_base_url = "http://127.0.0.1:1234/v1"
        c.llm_model = "qwen2.5-7b-instruct"
      end

      expect { described_class.health_check! }.not_to raise_error
    end
  end
end

RSpec.describe LocalBenchmark::ReaderLLM do
  it "calls configured LLM client" do
    client = Object.new
    client.define_singleton_method(:invoke) { |_prompt| Llmemory::LLM::Response.new("teal", usage: {}) }

    answer = described_class.new(client: client).call(question: "Color?", context: "favorite color is teal")
    expect(answer).to eq("teal")
  end
end
