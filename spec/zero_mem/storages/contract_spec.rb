# frozen_string_literal: true

RSpec.shared_examples "zero_mem trace storage contract" do |factory|
  let(:storage) { factory.call }
  let(:user_a) { "user_a" }
  let(:user_b) { "user_b" }
  let(:session_id) { "sess_1" }

  def write(user_id: user_a, content: "hello", role: :user, session: session_id, **extra)
    sequence = storage.next_sequence(user_id, session)
    trace = Llmemory::ZeroMem::Trace.build(
      user_id: user_id,
      session_id: session,
      role: role,
      content: content,
      sequence: sequence,
      **extra
    )
    storage.write_trace(trace)
    trace
  end

  it "writes, reads, lists and archives traces with user isolation" do
    t1 = write(content: "alpha")
    t2 = write(user_id: user_b, content: "beta")

    expect(storage.get_trace(user_a, t1.id).content).to eq("alpha")
    expect(storage.get_trace(user_a, t2.id)).to be_nil
    expect(storage.list_traces(user_a).map(&:id)).to eq([t1.id])

    expect(storage.archive_trace(user_a, t1.id)).to be(true)
    expect(storage.list_traces(user_a)).to be_empty
    expect(storage.list_traces(user_a, include_archived: true).map(&:id)).to eq([t1.id])
    expect(storage.get_trace(user_b, t2.id).content).to eq("beta")
  end

  it "enforces idempotency keys per user" do
    first = write(content: "once", idempotency_key: "k1")
    sequence = storage.next_sequence(user_a, session_id)
    duplicate_attempt = Llmemory::ZeroMem::Trace.build(
      user_id: user_a,
      session_id: session_id,
      role: :user,
      content: "once",
      sequence: sequence,
      idempotency_key: "k1"
    )
    storage.write_trace(duplicate_attempt)
    expect(storage.list_traces(user_a).size).to eq(1)
    expect(storage.find_by_idempotency_key(user_a, "k1").id).to eq(first.id)
  end

  it "orders by session sequence" do
    write(content: "one")
    write(content: "two")
    contents = storage.list_traces(user_a).map(&:content)
    expect(contents).to eq(%w[one two])
  end
end
