# frozen_string_literal: true

require "tempfile"
require_relative "contract_spec"

require "llmemory/zero_mem/storages/file"

RSpec.describe Llmemory::ZeroMem::Storages::FileStorage do
  include_examples "zero_mem trace storage contract", lambda {
    dir = Dir.mktmpdir
    described_class.new(base_path: dir, cipher: Llmemory::Crypto::NullCipher.new)
  }

  it "persists encrypted snapshots round-trip" do
    dir = Dir.mktmpdir
    cipher = Llmemory::Crypto::Cipher.new("zm6-file-spec-key")
    store = described_class.new(base_path: dir, cipher: cipher)
    trace = Llmemory::ZeroMem::Trace.build(
      user_id: "u1",
      session_id: "s1",
      role: :user,
      content: "persist me",
      sequence: 1
    )
    store.write_trace(trace)

    reloaded = described_class.new(base_path: dir, cipher: cipher)
    expect(reloaded.get_trace("u1", trace.id).content).to eq("persist me")
    expect(File.read(File.join(dir, "zero_mem", "snapshot.json"))).to include("enc:v1:")
  end
end
