# frozen_string_literal: true

RSpec.describe Llmemory::Memory do
  let(:user_id) { "user_123" }
  let(:session_id) { "conv_456" }

  describe "#add_message and #messages" do
    let(:memory) { described_class.new(user_id: user_id, session_id: session_id) }

    it "adds user and assistant messages and returns them" do
      expect(memory.messages).to eq([])
      memory.add_message(role: :user, content: "Soy vegano")
      memory.add_message(role: :assistant, content: "Entendido")
      msgs = memory.messages
      expect(msgs.size).to eq(2)
      expect(msgs[0]).to eq({ role: :user, content: "Soy vegano" })
      expect(msgs[1]).to eq({ role: :assistant, content: "Entendido" })
    end

    it "persists messages across instances when using shared checkpoint store" do
      shared_store = Llmemory::ShortTerm::Stores::MemoryStore.new
      checkpoint = Llmemory::ShortTerm::Checkpoint.new(user_id: user_id, session_id: session_id, store: shared_store)
      described_class.new(user_id: user_id, session_id: session_id, checkpoint: checkpoint).add_message(role: :user, content: "Hola")
      checkpoint2 = Llmemory::ShortTerm::Checkpoint.new(user_id: user_id, session_id: session_id, store: shared_store)
      memory2 = described_class.new(user_id: user_id, session_id: session_id, checkpoint: checkpoint2)
      expect(memory2.messages.map { |m| m[:content] }).to eq(["Hola"])
    end
  end

  describe "#retrieve" do
    let(:memory) { described_class.new(user_id: user_id, session_id: session_id) }

    it "returns short-term conversation context when no long-term memories" do
      memory.add_message(role: :user, content: "¿Qué tal?")
      memory.add_message(role: :assistant, content: "Bien")
      context = memory.retrieve("short query")
      expect(context).to include("=== RECENT CONVERSATION ===")
      expect(context).to include("user: ¿Qué tal?")
      expect(context).to include("assistant: Bien")
      expect(context).to include("=== END RECENT CONVERSATION ===")
    end

    it "returns combined context when long-term has data" do
      long_term_double = double("LongTerm").tap do |lt|
        allow(lt).to receive(:search_candidates).with(anything, user_id: user_id, top_k: 20).and_return([
          { text: "User is vegan", timestamp: Time.now, score: 1.0 }
        ])
        allow(lt).to receive(:user_id).and_return(user_id)
      end
      retrieval_engine = Llmemory::Retrieval::Engine.new(long_term_double)
      memory = described_class.new(user_id: user_id, session_id: session_id, retrieval_engine: retrieval_engine)
      memory.add_message(role: :user, content: "Hola")
      context = memory.retrieve("preferencias", max_tokens: 500)
      expect(context).to include("RECENT CONVERSATION")
      expect(context).to include("RELEVANT MEMORIES")
      expect(context).to include("User is vegan")
    end
  end

  describe "#consolidate!" do
    it "calls long-term memorize with conversation text" do
      long_term_double = double("LongTerm").tap do |lt|
        expect(lt).to receive(:memorize).with("user: Soy vegano\nassistant: Ok")
      end
      memory = described_class.new(user_id: user_id, session_id: session_id, long_term: long_term_double)
      memory.add_message(role: :user, content: "Soy vegano")
      memory.add_message(role: :assistant, content: "Ok")
      memory.consolidate!
    end

    it "returns true and does not call long_term when messages are empty" do
      long_term_double = double("LongTerm")
      allow(long_term_double).to receive(:memorize)
      memory = described_class.new(user_id: user_id, session_id: session_id, long_term: long_term_double)
      expect(memory.consolidate!).to be true
      expect(long_term_double).not_to have_received(:memorize)
    end
  end

  describe "#clear_session!" do
    it "clears short-term messages but long-term is unchanged" do
      long_term_storage = Llmemory::LongTerm::FileBased::Storage.new
      long_term = Llmemory::LongTerm::FileBased::Memory.new(user_id: user_id, storage: long_term_storage)
      memory = described_class.new(user_id: user_id, session_id: session_id, long_term: long_term)
      memory.add_message(role: :user, content: "Test")
      expect(memory.messages.size).to eq(1)
      memory.clear_session!
      expect(memory.messages).to eq([])
    end

    it "returns true" do
      memory = described_class.new(user_id: user_id, session_id: session_id)
      expect(memory.clear_session!).to be true
    end
  end

  describe "#prune!" do
    it "returns false when prune_tool_results_enabled is false" do
      allow(Llmemory.configuration).to receive(:prune_tool_results_enabled).and_return(false)
      memory = described_class.new(user_id: user_id, session_id: session_id)
      memory.add_message(role: :tool_result, content: "x" * 5000)
      expect(memory.prune!).to be false
    end

    it "persists pruned tool results when enabled" do
      allow(Llmemory.configuration).to receive(:prune_tool_results_enabled).and_return(true)
      allow(Llmemory.configuration).to receive(:prune_tool_results_mode).and_return(:hard_clear)
      allow(Llmemory.configuration).to receive(:prune_tool_results_max_bytes).and_return(2048)

      memory = described_class.new(user_id: user_id, session_id: session_id)
      memory.add_message(role: :user, content: "Hi")
      memory.add_message(role: :tool_result, content: "Long output " * 500)

      expect(memory.prune!).to be true
      msgs = memory.messages
      expect(msgs.find { |m| m[:role] == :tool_result }[:content]).to eq("[Tool result pruned]")
    end
  end

  describe "#context_tokens and #should_auto_consolidate?" do
    it "returns estimated token count" do
      memory = described_class.new(user_id: user_id, session_id: session_id)
      memory.add_message(role: :user, content: "Hello")
      memory.add_message(role: :assistant, content: "Hi")
      expect(memory.context_tokens).to be >= 1
    end

    it "should_auto_consolidate? returns true when over threshold" do
      allow(Llmemory.configuration).to receive(:context_window_tokens).and_return(1000)
      allow(Llmemory.configuration).to receive(:reserve_tokens).and_return(900)

      memory = described_class.new(user_id: user_id, session_id: session_id)
      50.times { |i| memory.add_message(role: :user, content: "Message #{i} with enough content to exceed threshold") }

      expect(memory.should_auto_consolidate?).to be true
    end

    it "should_auto_consolidate? returns false when under threshold" do
      allow(Llmemory.configuration).to receive(:context_window_tokens).and_return(100_000)
      allow(Llmemory.configuration).to receive(:reserve_tokens).and_return(90_000)

      memory = described_class.new(user_id: user_id, session_id: session_id)
      memory.add_message(role: :user, content: "Hi")

      expect(memory.should_auto_consolidate?).to be false
    end
  end

  describe "#with_overflow_recovery" do
    it "yields and returns result when overflow_recovery disabled" do
      memory = described_class.new(user_id: user_id, session_id: session_id)
      result = memory.with_overflow_recovery { 42 }
      expect(result).to eq(42)
    end

    it "retries on LLMError with context/token overflow when enabled" do
      allow(Llmemory.configuration).to receive(:overflow_recovery_enabled).and_return(true)
      allow(Llmemory.configuration).to receive(:prune_tool_results_enabled).and_return(false)

      llm_double = double("LLM")
      call_count = 0
      allow(llm_double).to receive(:invoke) do
        call_count += 1
        raise Llmemory::LLMError, "context length exceeded" if call_count == 1
        "Summary"
      end
      allow(Llmemory::LLM).to receive(:client).and_return(llm_double)

      memory = described_class.new(user_id: user_id, session_id: session_id)
      15.times { |i| memory.add_message(role: :user, content: "Message #{i} with content") }

      result = memory.with_overflow_recovery do
        memory.send(:llm_client).invoke("Summarize this")
      end
      expect(result).to eq("Summary")
      expect(call_count).to be >= 2
    end

    it "re-raises LLMError when message is not overflow-related" do
      allow(Llmemory.configuration).to receive(:overflow_recovery_enabled).and_return(true)

      llm_double = double("LLM")
      allow(llm_double).to receive(:invoke).and_raise(Llmemory::LLMError, "Rate limit exceeded")

      allow(Llmemory::LLM).to receive(:client).and_return(llm_double)
      memory = described_class.new(user_id: user_id, session_id: session_id)

      expect do
        memory.with_overflow_recovery { memory.send(:llm_client).invoke("test") }
      end.to raise_error(Llmemory::LLMError, /Rate limit/)
    end

    it "re-raises after max retries exceeded" do
      allow(Llmemory.configuration).to receive(:overflow_recovery_enabled).and_return(true)
      allow(Llmemory.configuration).to receive(:prune_tool_results_enabled).and_return(false)

      llm_double = double("LLM")
      allow(llm_double).to receive(:invoke).and_raise(Llmemory::LLMError, "context length exceeded")
      allow(Llmemory::LLM).to receive(:client).and_return(llm_double)

      memory = described_class.new(user_id: user_id, session_id: session_id)
      5.times { |i| memory.add_message(role: :user, content: "Message #{i}") }

      expect do
        memory.with_overflow_recovery(max_retries: 2) { memory.send(:llm_client).invoke("test") }
      end.to raise_error(Llmemory::LLMError, /context length/)
    end
  end

  describe "#check_context_window!" do
    it "triggers consolidate and compact when over threshold" do
      allow(Llmemory.configuration).to receive(:context_window_tokens).and_return(500)
      allow(Llmemory.configuration).to receive(:reserve_tokens).and_return(400)
      allow(Llmemory.configuration).to receive(:memory_flush_enabled).and_return(true)
      allow(Llmemory.configuration).to receive(:memory_flush_threshold_tokens).and_return(10)
      allow(Llmemory.configuration).to receive(:compact_max_bytes).and_return(100)

      long_term_double = double("LongTerm")
      allow(long_term_double).to receive(:memorize)

      llm_double = double("LLM")
      allow(llm_double).to receive(:invoke).and_return("Summary")
      allow(Llmemory::LLM).to receive(:client).and_return(llm_double)

      memory = described_class.new(user_id: user_id, session_id: session_id, long_term: long_term_double)
      30.times { |i| memory.add_message(role: :user, content: "Message #{i} with content to exceed limits") }

      result = memory.check_context_window!
      expect(result).to be true
    end
  end

  describe "#recall_for and #last_user_message" do
    it "returns empty when auto_recall_enabled is false" do
      allow(Llmemory.configuration).to receive(:auto_recall_enabled).and_return(false)
      memory = described_class.new(user_id: user_id, session_id: session_id)
      memory.add_message(role: :user, content: "Hello")
      expect(memory.recall_for).to eq("")
    end

    it "returns context when auto_recall_enabled and query provided" do
      allow(Llmemory.configuration).to receive(:auto_recall_enabled).and_return(true)
      long_term_double = double("LongTerm").tap do |lt|
        allow(lt).to receive(:search_candidates).with(anything, user_id: user_id, top_k: 20).and_return([
          { text: "User prefers Python", timestamp: Time.now, score: 1.0 }
        ])
        allow(lt).to receive(:user_id).and_return(user_id)
      end
      retrieval_engine = Llmemory::Retrieval::Engine.new(long_term_double)
      memory = described_class.new(user_id: user_id, session_id: session_id, long_term: long_term_double, retrieval_engine: retrieval_engine)
      memory.add_message(role: :user, content: "Hi")

      context = memory.recall_for(query: "preferences")
      expect(context).to include("User prefers Python")
    end

    it "uses last user message as query when query is nil" do
      allow(Llmemory.configuration).to receive(:auto_recall_enabled).and_return(true)
      long_term_double = double("LongTerm").tap do |lt|
        allow(lt).to receive(:search_candidates).with("my preferences", user_id: user_id, top_k: 20).and_return([
          { text: "User likes coffee", timestamp: Time.now, score: 1.0 }
        ])
        allow(lt).to receive(:user_id).and_return(user_id)
      end
      retrieval_engine = Llmemory::Retrieval::Engine.new(long_term_double)
      memory = described_class.new(user_id: user_id, session_id: session_id, long_term: long_term_double, retrieval_engine: retrieval_engine)
      memory.add_message(role: :user, content: "my preferences")
      memory.add_message(role: :assistant, content: "Let me check")

      context = memory.recall_for
      expect(context).to include("User likes coffee")
    end

    it "last_user_message returns the most recent user message" do
      memory = described_class.new(user_id: user_id, session_id: session_id)
      memory.add_message(role: :user, content: "First")
      memory.add_message(role: :assistant, content: "Ok")
      memory.add_message(role: :user, content: "Second")
      expect(memory.last_user_message).to eq("Second")
    end
  end

  describe "#user_id" do
    it "returns the given user_id" do
      memory = described_class.new(user_id: user_id, session_id: session_id)
      expect(memory.user_id).to eq(user_id)
    end
  end

  describe "api_key" do
    it "builds LLM client with the given API key and passes it to long-term and retrieval" do
      llm_double = double("LLM")
      expect(Llmemory::LLM).to receive(:client).with(api_key: "sk-custom-key").and_return(llm_double)
      memory = described_class.new(user_id: user_id, session_id: session_id, api_key: "sk-custom-key")
      expect(memory).to be_a(described_class)
      long_term = memory.instance_variable_get(:@long_term)
      expect(long_term.instance_variable_get(:@llm)).to eq(llm_double)
    end

    it "does not build a custom LLM client when api_key is nil" do
      expect(Llmemory::LLM).not_to receive(:client).with(api_key: anything)
      described_class.new(user_id: user_id, session_id: session_id)
    end
  end

  describe "#maybe_flush_memory!" do
    it "returns false and does not consolidate when under threshold" do
      allow(Llmemory.configuration).to receive(:memory_flush_enabled).and_return(true)
      allow(Llmemory.configuration).to receive(:memory_flush_threshold_tokens).and_return(10_000)

      long_term_double = double("LongTerm")
      allow(long_term_double).to receive(:memorize)
      memory = described_class.new(user_id: user_id, session_id: session_id, long_term: long_term_double)
      memory.add_message(role: :user, content: "Hi")
      memory.add_message(role: :assistant, content: "Hello")

      expect(memory.maybe_flush_memory!).to be false
      expect(long_term_double).not_to have_received(:memorize)
    end

    it "returns true and consolidates when over threshold" do
      allow(Llmemory.configuration).to receive(:memory_flush_enabled).and_return(true)
      allow(Llmemory.configuration).to receive(:memory_flush_threshold_tokens).and_return(10)

      long_term_double = double("LongTerm")
      expect(long_term_double).to receive(:memorize).with(/\Auser:.*assistant:/m)
      memory = described_class.new(user_id: user_id, session_id: session_id, long_term: long_term_double)
      memory.add_message(role: :user, content: "This is a long message that exceeds the token threshold for flush")
      memory.add_message(role: :assistant, content: "Another long response to ensure we pass the threshold")

      expect(memory.maybe_flush_memory!).to be true
    end

    it "returns false when memory_flush_enabled is false" do
      allow(Llmemory.configuration).to receive(:memory_flush_enabled).and_return(false)
      allow(Llmemory.configuration).to receive(:memory_flush_threshold_tokens).and_return(10)

      long_term_double = double("LongTerm")
      allow(long_term_double).to receive(:memorize)
      memory = described_class.new(user_id: user_id, session_id: session_id, long_term: long_term_double)
      memory.add_message(role: :user, content: "Long message " * 50)

      expect(memory.maybe_flush_memory!).to be false
      expect(long_term_double).not_to have_received(:memorize)
    end
  end

  describe "#compact!" do
    let(:memory) { described_class.new(user_id: user_id, session_id: session_id) }

    it "returns false when messages byte size is within max" do
      memory.add_message(role: :user, content: "Hello")
      memory.add_message(role: :assistant, content: "Hi there")
      expect(memory.compact!(max_bytes: 10_000)).to be false
      expect(memory.messages.size).to eq(2)
    end

    it "compacts messages when byte size exceeds max" do
      allow(Llmemory.configuration).to receive(:memory_flush_enabled).and_return(false)

      llm_double = double("LLM")
      allow(llm_double).to receive(:invoke).and_return("Summary of old conversation")
      allow(Llmemory::LLM).to receive(:client).and_return(llm_double)

      10.times { |i| memory.add_message(role: :user, content: "Message number #{i} with some extra content to increase size") }
      original_size = memory.messages.size
      expect(original_size).to eq(10)

      result = memory.compact!(max_bytes: 200)
      expect(result).to be true

      msgs = memory.messages
      expect(msgs.size).to be < original_size
      expect(msgs.first[:role]).to eq(:system)
      expect(msgs.first[:content]).to eq("Summary of old conversation")
    end

    it "calls consolidate! before compacting when over memory_flush_threshold_tokens" do
      allow(Llmemory.configuration).to receive(:memory_flush_enabled).and_return(true)
      allow(Llmemory.configuration).to receive(:memory_flush_threshold_tokens).and_return(50)

      long_term_double = double("LongTerm")
      expect(long_term_double).to receive(:memorize).with(include("Message number 0"))

      llm_double = double("LLM")
      allow(llm_double).to receive(:invoke).and_return("Summary of old conversation")
      allow(Llmemory::LLM).to receive(:client).and_return(llm_double)

      memory = described_class.new(user_id: user_id, session_id: session_id, long_term: long_term_double)
      10.times { |i| memory.add_message(role: :user, content: "Message number #{i} with extra content to exceed threshold") }

      result = memory.compact!(max_bytes: 200)
      expect(result).to be true
    end

    it "uses configuration default when max_bytes not provided" do
      allow(Llmemory.configuration).to receive(:compact_max_bytes).and_return(100)
      allow(Llmemory.configuration).to receive(:memory_flush_enabled).and_return(false)

      llm_double = double("LLM")
      allow(llm_double).to receive(:invoke).and_return("Summarized")
      allow(Llmemory::LLM).to receive(:client).and_return(llm_double)

      5.times { |i| memory.add_message(role: :user, content: "Message #{i} with enough content to exceed limit") }
      expect(memory.compact!).to be true
    end

    it "falls back to truncated text on LLM error" do
      allow(Llmemory.configuration).to receive(:memory_flush_enabled).and_return(false)

      llm_double = double("LLM")
      allow(llm_double).to receive(:invoke).and_raise(Llmemory::LLMError.new("API error"))
      allow(Llmemory::LLM).to receive(:client).and_return(llm_double)

      10.times { |i| memory.add_message(role: :user, content: "Message #{i} with content") }
      result = memory.compact!(max_bytes: 200)
      expect(result).to be true

      msgs = memory.messages
      expect(msgs.first[:role]).to eq(:system)
      expect(msgs.first[:content]).to include("user: Message 0")
    end

    it "skips flush when last_compact_at is within flush_once_per_cycle_seconds" do
      allow(Llmemory.configuration).to receive(:memory_flush_enabled).and_return(true)
      allow(Llmemory.configuration).to receive(:memory_flush_threshold_tokens).and_return(50)
      allow(Llmemory.configuration).to receive(:flush_once_per_cycle_seconds).and_return(60)

      long_term_double = double("LongTerm")
      allow(long_term_double).to receive(:memorize)
      expect(long_term_double).to receive(:memorize).exactly(1).time

      llm_double = double("LLM")
      allow(llm_double).to receive(:invoke).and_return("Summary")
      allow(Llmemory::LLM).to receive(:client).and_return(llm_double)

      memory = described_class.new(user_id: user_id, session_id: session_id, long_term: long_term_double)
      10.times { |i| memory.add_message(role: :user, content: "Message #{i} with extra content to exceed threshold") }
      memory.compact!(max_bytes: 200)

      10.times { |i| memory.add_message(role: :user, content: "More message #{i} with extra content") }
      memory.compact!(max_bytes: 200)
    end
  end

  describe "#messages with message_sanitizer_enabled" do
    it "sanitizes messages when message_sanitizer_enabled is true" do
      allow(Llmemory.configuration).to receive(:message_sanitizer_enabled).and_return(true)
      allow(Llmemory.configuration).to receive(:max_message_chars).and_return(50)

      memory = described_class.new(user_id: user_id, session_id: session_id)
      memory.add_message(role: :user, content: "Hi")
      memory.add_message(role: :assistant, content: "   ")
      memory.add_message(role: :user, content: "Bye")

      msgs = memory.messages
      expect(msgs.size).to eq(2)
      expect(msgs.map { |m| m[:content] }).to eq(["Hi", "Bye"])
    end

    it "returns unsanitized messages when message_sanitizer_enabled is false" do
      allow(Llmemory.configuration).to receive(:message_sanitizer_enabled).and_return(false)

      memory = described_class.new(user_id: user_id, session_id: session_id)
      memory.add_message(role: :user, content: "Hi")
      memory.add_message(role: :assistant, content: "   ")

      msgs = memory.messages
      expect(msgs.size).to eq(2)
    end
  end

  describe "long_term_type: :graph_based" do
    it "uses graph-based long-term memory when long_term_type is :graph_based" do
      long_term = described_class.new(user_id: user_id, session_id: session_id, long_term_type: :graph_based).instance_variable_get(:@long_term)
      expect(long_term).to be_a(Llmemory::LongTerm::GraphBased::Memory)
    end

    it "retrieve works with graph-based long-term (mocked)" do
      graph_long_term = double("GraphBased::Memory").tap do |lt|
        allow(lt).to receive(:search_candidates).with(anything, user_id: user_id, top_k: 20).and_return([
          { text: "User works_at OpenAI", timestamp: Time.now, score: 0.9 }
        ])
        allow(lt).to receive(:user_id).and_return(user_id)
      end
      retrieval_engine = Llmemory::Retrieval::Engine.new(graph_long_term)
      memory = described_class.new(user_id: user_id, session_id: session_id, long_term: graph_long_term, retrieval_engine: retrieval_engine)
      memory.add_message(role: :user, content: "Hi")
      context = memory.retrieve("where does user work", max_tokens: 500)
      expect(context).to include("User works_at OpenAI")
    end
  end
end
