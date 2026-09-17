# frozen_string_literal: true

require_relative "contract_spec"
require "llmemory/zero_mem/storages/active_record"

RSpec.describe Llmemory::ZeroMem::Storages::ActiveRecordStorage,
               skip: (defined?(ActiveRecord) ? false : "ActiveRecord not in bundle") do
  let(:cipher) { Llmemory::Crypto::Cipher.new("zero-mem-ar-spec") }

  it "loads ActiveRecord models for lazy require" do
    expect { described_class.load_models! }.not_to raise_error
  end

  it "encrypts content at rest when cipher is enabled", skip: "Requires Rails migration and DB" do
    storage = described_class.new(cipher: cipher)
    trace = Llmemory::ZeroMem::Trace.build(
      user_id: "u1",
      session_id: "s1",
      role: :user,
      content: "secret trace",
      sequence: 1
    )
    storage.write_trace(trace)
    raw = Llmemory::ZeroMem::Storages::LlmemoryTrace.find(trace.id)
    expect(raw.content).not_to include("secret trace")
    expect(raw.content).to include("enc:v1:")
    expect(storage.get_trace("u1", trace.id).content).to eq("secret trace")
  end
end
