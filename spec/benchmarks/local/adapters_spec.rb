# frozen_string_literal: true

require "json"
require "fileutils"
require "tmpdir"
require File.expand_path("../../../benchmarks/local/adapters/locomo", __dir__)
require File.expand_path("../../../benchmarks/local/adapters/longmemeval", __dir__)
require File.expand_path("../../../benchmarks/local/adapters/mem2act", __dir__)
require File.expand_path("../../../benchmarks/local/adapters/mem_syco", __dir__)
require File.expand_path("../../../benchmarks/local/adapters/group_mem_bench", __dir__)
require File.expand_path("../../../benchmarks/local/adapters/locomo_plus", __dir__)
require File.expand_path("../../../benchmarks/local/adapters/memory_agent_bench", __dir__)
require File.expand_path("../../../benchmarks/local/scorers/arena_match", __dir__)

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

  describe LocalBenchmark::Adapters::MemSyco do
    it "maps evaluation.reference_answer and memory items" do
      Dir.mktmpdir do |dir|
        row = {
          "id" => "v1",
          "question" => "Which option?",
          "dialogue" => [{ "role" => "user", "content" => "I dislike cooking for dates." }],
          "memory" => { "policy" => "use", "items" => [{ "content" => "User dislikes cooking for a date." }] },
          "evaluation" => { "reference_answer" => "Order takeout.", "rubric" => { "expected_behavior" => "no cooking" } }
        }
        File.write(File.join(dir, "personalized_memory_use.jsonl"), JSON.generate(row))

        adapter = described_class.new(root: dir)
        conv = adapter.conversations(limit: 1).first
        expect(conv["queries"].first["gold_answer"]).to eq("Order takeout.")
        expect(conv["sessions"].first["id"]).to eq("memory_items")
        expect(conv["queries"].first["metadata"]["rubric"]).to be_a(Hash)
      end
    end
  end

  describe LocalBenchmark::Adapters::GroupMemBench do
    it "reads hash-of-channel message arrays" do
      Dir.mktmpdir do |dir|
        channel = {
          "Regulatory" => [
            { "msg_node" => "Msg_1", "author" => "Alice", "content" => "Deadline is 2025-07-18.", "timestamp" => "2025-07-01" }
          ]
        }
        FileUtils.mkdir_p(File.join(dir, "data", "final", "Finance"))
        File.write(
          File.join(dir, "data", "final", "Finance", "synthetic_domain_channels_rolevariants_Finance.json"),
          JSON.generate(channel)
        )
        FileUtils.mkdir_p(File.join(dir, "questions", "Finance"))
        File.write(
          File.join(dir, "questions", "Finance", "multi_hop.jsonl"),
          JSON.generate({ "id" => "mh1", "question" => "Deadline?", "answer" => "2025-07-18" })
        )

        adapter = described_class.new(root: dir)
        conv = adapter.conversations(limit: 1).first
        expect(conv["sessions"].first["turns"].size).to eq(1)
        expect(conv["sessions"].first["turns"].first["id"]).to eq("Msg_1")
        expect(conv["consolidate_mode"]).to eq("per_session")
      end
    end
  end

  describe LocalBenchmark::Adapters::LoCoMoPlus do
    it "stitches locomo_plus cue into base conversation" do
      Dir.mktmpdir do |dir|
        locomo = [{
          "sample_id" => "conv-1",
          "conversation" => {
            "speaker_a" => "A",
            "speaker_b" => "B",
            "session_1_date_time" => "2023-05-08",
            "session_1" => [{ "speaker" => "A", "dia_id" => "D1:1", "text" => "Hello." }]
          },
          "qa" => []
        }]
        plus = [{
          "cue_dialogue" => "A: After learning to say 'no', I feel less stressed.",
          "trigger_query" => "A: I volunteered again and I'm overwhelmed.",
          "time_gap" => "two weeks later",
          "relation_type" => "causal"
        }]
        File.write(File.join(dir, "locomo10.json"), JSON.generate(locomo))
        File.write(File.join(dir, "locomo_plus.json"), JSON.generate(plus))

        adapter = described_class.new(root: dir)
        conv = adapter.conversations(limit: 1).first
        expect(conv["sessions"].map { |s| s["id"] }).to include("cue", "query", "s1")
        expect(conv["queries"].first["gold_trace_ids"]).to include("cue:1")
      end
    end
  end

  describe LocalBenchmark::Adapters::MemoryAgentBench do
    it "splits long context into per-session chunks" do
      Dir.mktmpdir do |dir|
        subset = File.join(dir, "Accurate_Retrieval")
        FileUtils.mkdir_p(subset)
        row = { "context" => "x" * 7000, "questions" => [{ "question" => "Q?", "answer" => "A" }] }
        File.write(File.join(subset, "sample.jsonl"), JSON.generate(row))

        adapter = described_class.new(root: dir)
        conv = adapter.conversations(limit: 1).first
        expect(conv["sessions"].size).to be >= 2
        expect(conv["consolidate_mode"]).to eq("per_session")
        expect(conv["queries"].first["gold_trace_ids"]).to eq([])
      end
    end
  end

  describe LocalBenchmark::Scorers::ArenaMatch do
    it "scores ASIN and attribute overlap" do
      gold = { "target_asin" => "B00TEST", "attributes" => %w[gold strawberry] }.to_json
      pred = "Product B00TEST with gold strawberry flavor"
      expect(described_class.score(pred, gold)).to eq(1.0)
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
