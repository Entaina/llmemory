# frozen_string_literal: true

# Raises on any generative LLM invoke — used to detect accidental calls in Zero-Mem paths.
class BombLLM
  def invoke(*)
    raise Llmemory::LLMError, "zero_mem bomb: unexpected generative invoke"
  end

  def embed(*)
    raise Llmemory::LLMError, "zero_mem bomb: unexpected embed invoke"
  end
end
