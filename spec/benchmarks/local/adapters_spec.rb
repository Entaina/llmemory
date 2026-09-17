# frozen_string_literal: true

require "json"
require "fileutils"
require "tmpdir"
require File.expand_path("../../../benchmarks/local/adapters/locomo", __dir__)
require File.expand_path("../../../benchmarks/local/adapters/longmemeval", __dir__)
require File.expand_path("../../../benchmarks/local/adapters/mem2act", __dir__)

RSpec.describe "LocalBenchmark adapters" do
  describe LocalBenchmark::Adapters::LoCoMo do
    it "normalizes locomo10 sample" do
      Dir.mktmpdir do |dir|
        sample = [{
          "sample_id" => "conv-test",
          "conversation" => {
            "speaker_a" => "Alice",
            "speaker_b" => "Bob",
            "session_1_date_time" => "2023-01-01",
            "session_1" => [{ "speaker" => "Alice", "dia_id" => "D1:1", "text" => "My color is teal." }]
          },
          "qa" => [{ "question" => "Color?", "answer" => "teal", "evidence" => ["D1:1"], "category" => 4 }]
        }]
        FileUtils.mkdir_p(File.join(dir, "data"))
        File.write(File.join(dir, "data/locomo10.json"), JSON.generate(sample))

        adapter = described_class.new(root: dir)
        conv = adapter.conversations(limit: 1).first
        expect(conv["id"]).to eq("conv-test")
        expect(conv["queries"].first["gold_answer"]).to eq("teal")
        expect(conv["sessions"].first["turns"].first["id"]).to eq("D1:1")
      end
    end

    it "skips when root missing" do
      adapter = described_class.new(root: "")
      expect(adapter.available?).to be(false)
    end
  end

  describe LocalBenchmark::Adapters::LongMemEval do
    it "loads oracle record" do
      Dir.mktmpdir do |dir|
        record = [{
          "question_id" => "q-1",
          "question" => "What is my color?",
          "answer" => "teal",
          "question_type" => "single-session-user",
          "haystack_session_ids" => ["s1"],
          "haystack_dates" => ["2024-01-01"],
          "haystack_sessions" => [[{ "role" => "user", "content" => "My color is teal.", "has_answer" => true }]],
          "answer_session_ids" => ["s1"]
        }]
        File.write(File.join(dir, "longmemeval_oracle.json"), JSON.generate(record))

        adapter = described_class.new(root: dir, split: "oracle")
        conv = adapter.conversations(limit: 1).first
        expect(conv["queries"].first["gold_answer"]).to eq("teal")
      end
    end
  end

  describe LocalBenchmark::Adapters::Mem2Act do
    it "parses qa jsonl" do
      Dir.mktmpdir do |dir|
        row = {
          "qa_id" => "qa1",
          "query" => "Book my usual restaurant",
          "evolution_chain" => [{ "fact_id" => "f1", "text" => "User prefers vegan food." }],
          "tool_call" => { "name" => "book_restaurant", "arguments" => { "diet" => "vegan" } },
          "target_tool_schema" => { "name" => "book_restaurant" }
        }
        File.write(File.join(dir, "qa_dataset.jsonl"), JSON.generate(row))

        adapter = described_class.new(root: dir)
        conv = adapter.conversations(limit: 1).first
        expect(conv["queries"].first["metadata"]["tool_name"]).to eq("book_restaurant")
      end
    end
  end
end
