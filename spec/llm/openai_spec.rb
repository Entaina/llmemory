# frozen_string_literal: true

RSpec.describe Llmemory::LLM::OpenAI do
  let(:client) { described_class.new(api_key: "test-key") }

  before do
    stub_request(:post, %r{https://api\.openai\.com.*/chat/completions})
      .with(headers: { "Authorization" => "Bearer test-key" })
      .to_return(
        status: 200,
        body: {
          choices: [{ message: { content: "Hi there!" } }],
          usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 }
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  it "invokes and returns content with usage" do
    response = client.invoke("Hello")
    expect(response.to_s).to eq("Hi there!")
    expect(response.usage.input_tokens).to eq(10)
    expect(response.usage.output_tokens).to eq(5)
    expect(response.usage.total_tokens).to eq(15)
    expect(client.last_usage.total_tokens).to eq(15)
  end

  context "when API returns error" do
    before do
      stub_request(:post, %r{https://api\.openai\.com.*/chat/completions})
        .to_return(status: 500, body: "Internal error")
    end

    it "raises LLMError" do
      expect { client.invoke("Hello") }.to raise_error(Llmemory::LLMError, /OpenAI API error/)
    end
  end

  describe "#invoke_with_json_schema" do
    before do
      stub_request(:post, %r{https://api\.openai\.com.*/chat/completions})
        .to_return(
          status: 200,
          body: {
            choices: [{ message: { content: '{"entities":[]}' } }],
            usage: { prompt_tokens: 20, completion_tokens: 8, total_tokens: 28 }
          }.to_json,
          headers: { "Content-Type" => "application/json" }
        )
    end

    it "returns parsed JSON and records usage" do
      result = client.invoke_with_json_schema("extract", { name: "test", schema: { type: "object" } })
      expect(result).to eq("entities" => [])
      expect(client.last_usage.total_tokens).to eq(28)
    end
  end
end
