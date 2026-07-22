# frozen_string_literal: true

require "spec_helper"

RSpec.describe Llmemory::LongTerm::GraphBased::Storages do
  after { Llmemory.reset_configuration! }

  it "builds memory storage for :memory" do
    storage = described_class.build(store: :memory)
    expect(storage).to be_a(Llmemory::LongTerm::GraphBased::Storages::MemoryStorage)
  end

  it "raises ConfigurationError for unsupported stores" do
    expect { described_class.build(store: :file) }
      .to raise_error(Llmemory::ConfigurationError, /supports long_term_store :memory or :active_record/)
    expect { described_class.build(store: :postgres) }
      .to raise_error(Llmemory::ConfigurationError, /supports long_term_store :memory or :active_record/)
  end
end
