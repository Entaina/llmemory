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
