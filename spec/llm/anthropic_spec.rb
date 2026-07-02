# frozen_string_literal: true

RSpec.describe Llmemory::LLM::Anthropic do
  let(:client) { described_class.new(api_key: "test-key", model: "claude-sonnet-4-6") }

  before do
    stub_request(:post, "https://api.anthropic.com/v1/messages")
      .with(headers: { "x-api-key" => "test-key" })
      .to_return(
        status: 200,
        body: { content: [{ text: "Hello from Claude" }] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  it "invokes and returns content" do
    expect(client.invoke("Hi")).to eq("Hello from Claude")
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
