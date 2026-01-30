# frozen_string_literal: true

RSpec.describe Llmemory::LLM::OpenAI do
  let(:client) { described_class.new(api_key: "test-key") }

  before do
    stub_request(:post, %r{https://api\.openai\.com.*/chat/completions})
      .with(headers: { "Authorization" => "Bearer test-key" })
      .to_return(
        status: 200,
        body: { choices: [{ message: { content: "Hi there!" } }] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  it "invokes and returns content" do
    expect(client.invoke("Hello")).to eq("Hi there!")
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
end
