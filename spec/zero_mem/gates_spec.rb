# frozen_string_literal: true

require "webmock/rspec"

RSpec.describe "Zero-Mem CI gates" do
  let(:trace_store) { Llmemory::ZeroMem::Storages::Memory.new }

  def zero_mem_memory(user_id: "u_gate")
    Llmemory::Memory.new(
      user_id: user_id,
      session_id: "s1",
      trace_store: trace_store,
      memory_mode: :hybrid
    )
  end

  def invoke_calls(memory)
    memory.llm_usage.dig(:invoke, :calls).to_i
  end

  it "keeps generative invoke calls at zero for trace write and retrieve" do
    memory = zero_mem_memory
    before = invoke_calls(memory)
    memory.add_message(role: :user, content: "Prefiero té verde.")
    memory.retrieve("té")
    memory.retrieve_evidence("té")
    expect(invoke_calls(memory) - before).to eq(0)
  end

  it "returns resolvable trace_ids for every evidence item on fixtures" do
    conv = ZeroMem::FixtureLoader.load_conversation_by_id("es_single_hop_01")
    memory = zero_mem_memory(user_id: "u_fix")
    Array(conv["sessions"]).first["turns"].each do |turn|
      memory.record_trace(
        role: turn["role"],
        content: turn["content"],
        idempotency_key: turn["id"],
        add_to_checkpoint: false
      )
    end
    result = memory.retrieve_evidence(conv["queries"].first["text"])
    result.evidence.each do |ev|
      expect(trace_store.get_trace(memory.user_id, ev.trace_id)).not_to be_nil
    end
  end

  it "isolates tenants on retrieve_evidence" do
    mem_a = zero_mem_memory(user_id: "u_a")
    mem_b = zero_mem_memory(user_id: "u_b")
    mem_a.add_message(role: :user, content: "secret alpha")
    mem_b.add_message(role: :user, content: "secret beta")
    ids = mem_a.retrieve_evidence("alpha").evidence.map(&:trace_id)
    ids.each do |tid|
      expect(trace_store.get_trace("u_a", tid)).not_to be_nil
      expect(trace_store.get_trace("u_b", tid)).to be_nil
    end
  end

  it "is deterministic for repeated retrieve_evidence calls" do
    memory = zero_mem_memory
    memory.add_message(role: :user, content: "Atlas database Nimbus")
    q = "Which database does Atlas use?"
    a = memory.retrieve_evidence(q).evidence.map(&:trace_id)
    b = memory.retrieve_evidence(q).evidence.map(&:trace_id)
    expect(a).to eq(b)
  end

  it "marks sidecar circuit open after HTTP failures" do
    stub_request(:post, "http://127.0.0.1:8765/ner").to_return(status: 500, body: "fail")
    client = Llmemory::ZeroMem::SidecarClient.new(
      base_url: "http://127.0.0.1:8765",
      breaker: Llmemory::ZeroMem::CircuitBreaker.new(failure_threshold: 1)
    )
    expect { client.post_json("/ner", { text: "x" }) }.to raise_error(Llmemory::StoreError)
    expect(client.degraded?).to be(true)
  end
end
