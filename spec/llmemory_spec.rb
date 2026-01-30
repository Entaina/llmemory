# frozen_string_literal: true

RSpec.describe Llmemory do
  it "has a version number" do
    expect(Llmemory::VERSION).not_to be nil
  end

  it "configures via block" do
    Llmemory.configure do |config|
      config.llm_provider = :openai
      config.llm_model = "gpt-4"
    end
    expect(Llmemory.configuration.llm_model).to eq("gpt-4")
    Llmemory.reset_configuration!
  end
end
