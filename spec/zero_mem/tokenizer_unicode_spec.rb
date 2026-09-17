# frozen_string_literal: true

RSpec.describe "Unicode tokenizer (Zero-Mem ZM2)" do
  it "keeps ASCII regression tokens" do
    expect(Llmemory::Tokenizer.tokenize("Revert a Bad Deploy!")).to eq(%w[revert bad deploy])
  end

  it "preserves accented letters" do
    tokens = Llmemory::Tokenizer.tokenize("Trabajo en Medellín")
    expect(tokens).to include("trabajo", "medellín")
    expect(tokens).not_to include("medell")
  end

  it "extracts numeric tokens" do
    expect(Llmemory::Tokenizer.tokenize("calle nº 42")).to include("42")
  end

  it "tokenizes CJK without empty output" do
    expect(Llmemory::Tokenizer.tokenize("東京都")).not_to be_empty
  end
end
