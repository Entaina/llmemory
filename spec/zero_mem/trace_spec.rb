# frozen_string_literal: true

require "digest"

RSpec.describe Llmemory::ZeroMem::Trace do
  after { Llmemory.reset_configuration! }

  it "builds content hash and monotonic fields" do
    trace = described_class.build(
      user_id: "u1",
      session_id: "s1",
      role: :user,
      content: "Hola",
      sequence: 3
    )
    expect(trace.content_sha256).to eq(Digest::SHA256.hexdigest("Hola"))
    expect(trace.sequence).to eq(3)
  end

  it "rejects invalid UTF-8" do
    bad = "bad\xFF".dup.force_encoding("ASCII-8BIT")
    expect {
      described_class.build(user_id: "u1", session_id: "s1", role: :user, content: bad, sequence: 1)
    }.to raise_error(Llmemory::ZeroMem::ValidationError, /UTF-8/)
  end

  it "respects max_message_chars" do
    Llmemory.configure { |c| c.max_message_chars = 5 }
    expect {
      described_class.build(user_id: "u1", session_id: "s1", role: :user, content: "123456", sequence: 1)
    }.to raise_error(Llmemory::ZeroMem::ValidationError, /max_message_chars/)
  end
end
