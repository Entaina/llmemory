# frozen_string_literal: true

RSpec.describe Llmemory::ZeroMem::BudgetAssembler do
  let(:assembler) { described_class.new }

  def ev(content)
    Llmemory::ZeroMem::Evidence.new(
      trace_id: "tr_1",
      content: content,
      role: :user,
      session_id: "s1",
      occurred_at: Time.now,
      confidence: 1.0,
      score: 1.0
    )
  end

  it "skips an oversized item and keeps smaller ones" do
    small = ev("ok")
    huge = ev("word " * 500)
    tiny = ev("tail")
    selected = assembler.assemble([huge, small, tiny], max_tokens: 20)
    expect(selected.map(&:content)).to include("ok")
  end
end
