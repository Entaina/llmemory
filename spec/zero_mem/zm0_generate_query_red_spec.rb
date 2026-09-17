# frozen_string_literal: true

# Documents accidental generative LLM use in :classic paths today (ZM0 red tests).
# Fixed in ZM5 for :zero_mem; classic may still invoke until then.
RSpec.describe "ZM0 generative leak detection" do
  let(:long_query) do
    base = "Necesito recordar todos los detalles de la reserva, incluyendo hora, número de personas, " \
           "restricciones alimentarias y el nombre completo del restaurante para el seguimiento."
    raise "fixture query must exceed 100 chars" unless base.length > 100

    base
  end

  describe "Retrieval::Engine#generate_query" do
    let(:memory_double) do
      double("Memory", user_id: "u1").tap do |m|
        allow(m).to receive(:search_candidates).and_return([])
      end
    end
    let(:engine) { Llmemory::Retrieval::Engine.new(memory_double, llm: BombLLM.new) }

    it "calls generative invoke for queries longer than 100 characters" do
      invoked = false
      llm = Object.new
      llm.define_singleton_method(:invoke) do |*_args|
        invoked = true
        raise Llmemory::LLMError, "zero_mem bomb: unexpected generative invoke"
      end
      leaky_engine = Llmemory::Retrieval::Engine.new(memory_double, llm: llm)

      leaky_engine.retrieve_for_inference(long_query)
      expect(invoked).to be(true)
    end

    it "rescues LLMError inside generate_query and falls back to truncated text" do
      result = engine.send(:generate_query, long_query)
      expect(result).to eq(long_query[0..200])
    end

    it "does not call invoke for short queries" do
      invoked = false
      llm = Object.new
      llm.define_singleton_method(:invoke) { |*_args| invoked = true }
      short_engine = Llmemory::Retrieval::Engine.new(memory_double, llm: llm)

      short_engine.retrieve_for_inference("hola")
      expect(invoked).to be(false)
    end
  end

  describe "Memory#consolidate!" do
    it "calls generative invoke through fact extraction" do
      storage = Llmemory::LongTerm::FileBased::Storages::MemoryStorage.new
      long_term = Llmemory::LongTerm::FileBased::Memory.new(user_id: "u1", storage: storage, llm: BombLLM.new)
      memory = Llmemory::Memory.new(user_id: "u1", session_id: "s1", long_term: long_term)

      memory.add_message(role: :user, content: "Prefiero té sin azúcar.")
      expect { memory.consolidate! }.to raise_error(Llmemory::LLMError, /zero_mem bomb/)
    end
  end
end
