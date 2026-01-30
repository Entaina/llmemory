# frozen_string_literal: true

RSpec.describe Llmemory::VectorStore::OpenAIEmbeddings do
  let(:client) { described_class.new(api_key: "test-key") }

  before do
    stub_request(:post, "https://api.openai.com/embeddings")
      .with(
        headers: { "Authorization" => "Bearer test-key", "Content-Type" => "application/json" },
        body: "{\"input\":\"hello\",\"model\":\"text-embedding-3-small\"}"
      )
      .to_return(
        status: 200,
        body: { data: [{ embedding: [0.1] * 1536 }] }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  describe "#embed" do
    it "returns embedding vector from API" do
      result = client.embed("hello")
      expect(result).to be_an(Array)
      expect(result.size).to eq(1536)
      expect(result.first).to eq(0.1)
    end

    it "returns zero vector for empty text" do
      result = client.embed("   ")
      expect(result).to eq([0.0] * 1536)
      expect(a_request(:post, %r{embeddings})).not_to have_been_made
    end
  end

  context "when API returns error" do
    before do
      stub_request(:post, "https://api.openai.com/embeddings")
        .with(headers: { "Authorization" => "Bearer test-key" })
        .to_return(status: 500, body: "Internal error")
    end

    it "raises LLMError" do
      expect { client.embed("hello") }.to raise_error(Llmemory::LLMError, /Embeddings API/)
    end
  end
end
