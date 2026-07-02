# frozen_string_literal: true

RSpec.describe Llmemory::LLM::Anthropic do
  let(:client) { described_class.new(api_key: "test-key", model: "claude-sonnet-4-6") }

  before do
    stub_request(:post, "https://api.anthropic.com/v1/messages")
      .with(headers: { "x-api-key" => "test-key" })
      .to_return(
        status: 200,
        body: {
          content: [{ text: "Hello from Claude" }],
          usage: { input_tokens: 12, output_tokens: 8 }
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  it "invokes and returns content with usage" do
    response = client.invoke("Hi")
    expect(response.to_s).to eq("Hello from Claude")
    expect(response.usage.input_tokens).to eq(12)
    expect(response.usage.output_tokens).to eq(8)
    expect(response.usage.total_tokens).to eq(20)
    expect(client.last_usage.total_tokens).to eq(20)
  end

  context "when API returns error" do
    before do
      stub_request(:post, %r{https://api\.anthropic\.com/v1/messages})
        .to_return(status: 401, body: "Unauthorized")
    end

    it "raises LLMError" do
      expect { client.invoke("Hi") }.to raise_error(Llmemory::LLMError, /Anthropic API error/)
    end
  end
end
