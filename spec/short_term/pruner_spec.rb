# frozen_string_literal: true

RSpec.describe Llmemory::ShortTerm::Pruner do
  let(:pruner) { described_class.new(soft_trim_max_bytes: 100) }

  describe "#prune!" do
    it "leaves user and assistant messages unchanged" do
      messages = [
        { role: :user, content: "Hello" },
        { role: :assistant, content: "Hi there" }
      ]
      result = pruner.prune!(messages, mode: :soft_trim)
      expect(result[0][:content]).to eq("Hello")
      expect(result[1][:content]).to eq("Hi there")
    end

    it "soft-trims oversized tool_result messages" do
      long_content = "x" * 500
      messages = [
        { role: :user, content: "Run tool" },
        { role: :tool_result, content: long_content }
      ]
      result = pruner.prune!(messages, mode: :soft_trim)
      expect(result[0][:content]).to eq("Run tool")
      expect(result[1][:content]).to include("...")
      expect(result[1][:content].bytesize).to be < 500
    end

    it "hard-clears tool_result when mode is hard_clear" do
      messages = [
        { role: :tool_result, content: "Very long tool output " * 100 }
      ]
      result = pruner.prune!(messages, mode: :hard_clear)
      expect(result[0][:content]).to eq("[Tool result pruned]")
    end

    it "does not trim tool_result when under max_bytes" do
      messages = [
        { role: :tool_result, content: "short" }
      ]
      result = pruner.prune!(messages, mode: :soft_trim)
      expect(result[0][:content]).to eq("short")
    end
  end
end
