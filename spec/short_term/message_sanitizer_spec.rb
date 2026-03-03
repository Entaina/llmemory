# frozen_string_literal: true

RSpec.describe Llmemory::ShortTerm::MessageSanitizer do
  let(:sanitizer) { described_class.new(max_message_chars: 50) }

  describe "#sanitize!" do
    it "removes empty messages" do
      msgs = [
        { role: :user, content: "Hi" },
        { role: :assistant, content: "   " },
        { role: :user, content: "Bye" }
      ]
      result = sanitizer.sanitize!(msgs)
      expect(result.size).to eq(2)
      expect(result.map { |m| m[:content] }).to eq(["Hi", "Bye"])
    end

    it "caps content at max_message_chars" do
      msgs = [{ role: :user, content: "x" * 100 }]
      result = sanitizer.sanitize!(msgs)
      expect(result.first[:content].length).to eq(50)
    end

    it "removes orphaned tool_result without preceding tool" do
      msgs = [
        { role: :user, content: "Run" },
        { role: :tool_result, content: "Result without tool call" }
      ]
      result = sanitizer.sanitize!(msgs)
      expect(result.map { |m| m[:role] }).to eq([:user])
    end

    it "keeps tool_result when preceded by tool" do
      msgs = [
        { role: :tool, content: "get_weather" },
        { role: :tool_result, content: "Sunny" }
      ]
      result = sanitizer.sanitize!(msgs)
      expect(result.size).to eq(2)
    end

    it "removes orphaned tool_results in sequence" do
      msgs = [
        { role: :user, content: "Hi" },
        { role: :tool_result, content: "Orphan 1" },
        { role: :tool_result, content: "Orphan 2" },
        { role: :assistant, content: "Hello" }
      ]
      result = sanitizer.sanitize!(msgs)
      expect(result.map { |m| m[:role] }).to eq([:user, :assistant])
    end

    it "keeps tool/tool_result pairs in sequence" do
      msgs = [
        { role: :tool, content: "call" },
        { role: :tool_result, content: "Result" },
        { role: :tool, content: "call2" },
        { role: :tool_result, content: "Result2" }
      ]
      result = sanitizer.sanitize!(msgs)
      expect(result.size).to eq(4)
    end
  end
end
