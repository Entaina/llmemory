# frozen_string_literal: true

RSpec.describe Llmemory::VectorStore::OpenAIEmbeddings do
  let(:client) { described_class.new(api_key: "test-key") }

  before do
    stub_request(:post, "https://api.openai.com/v1/embeddings")
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
      stub_request(:post, "https://api.openai.com/v1/embeddings")
        .with(headers: { "Authorization" => "Bearer test-key" })
        .to_return(status: 500, body: "Internal error")
    end

    it "raises LLMError" do
      expect { client.embed("hello") }.to raise_error(Llmemory::LLMError, /Embeddings API/)
    end
  end

  describe "embedding cache" do
    it "returns cached embedding on second call when cache enabled" do
      allow(Llmemory.configuration).to receive(:embedding_cache_enabled).and_return(true)

      result1 = client.embed("hello")
      result2 = client.embed("hello")

      expect(result1).to eq(result2)
      expect(a_request(:post, %r{embeddings}).with(body: hash_including("input" => "hello"))).to have_been_made.times(1)
    end

    it "makes API call on each request when cache disabled" do
      allow(Llmemory.configuration).to receive(:embedding_cache_enabled).and_return(false)

      client.embed("hello")
      client.embed("hello")

      expect(a_request(:post, %r{embeddings})).to have_been_made.times(2)
    end

    it "does not cache different texts" do
      allow(Llmemory.configuration).to receive(:embedding_cache_enabled).and_return(true)

      stub_request(:post, "https://api.openai.com/v1/embeddings")
        .with(body: hash_including("input" => "world"))
        .to_return(
          status: 200,
          body: { data: [{ embedding: [0.2] * 1536 }] }.to_json,
          headers: { "Content-Type" => "application/json" }
        )

      client.embed("hello")
      client.embed("world")

      expect(a_request(:post, %r{embeddings})).to have_been_made.times(2)
    end
  end
end
