# frozen_string_literal: true

RSpec.describe BombLLM do
  it "raises on invoke" do
    bomb = described_class.new
    expect { bomb.invoke("anything") }.to raise_error(Llmemory::LLMError, /zero_mem bomb: unexpected generative invoke/)
  end

  it "raises on embed" do
    bomb = described_class.new
    expect { bomb.embed("anything") }.to raise_error(Llmemory::LLMError, /zero_mem bomb: unexpected embed invoke/)
  end

  it "does not raise when a separate embed double is used without invoke" do
    embed_only = double("EmbedOnly", embed: [0.1, 0.2])
    expect(embed_only.embed("hello")).to eq([0.1, 0.2])
  end
end
