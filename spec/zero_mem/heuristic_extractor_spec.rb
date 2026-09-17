# frozen_string_literal: true

RSpec.describe Llmemory::ZeroMem::Extractors::Heuristic do
  let(:extractor) { described_class.new }

  it "is not generative" do
    expect(extractor.generative?).to be(false)
  end

  it "extracts capitalized entities in English" do
    ents = extractor.extract("Project Atlas uses the Nimbus database.")
    keys = ents.map { |e| e[:normalized] }
    expect(keys).to include("project atlas", "nimbus")
  end

  it "preserves accented forms" do
    ents = extractor.extract("Trabajo en Medellín con Ana")
    keys = ents.map { |e| e[:normalized] }
    expect(keys.any? { |k| k.include?("medell") }).to be(true)
  end
end
