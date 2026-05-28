# frozen_string_literal: true

module Llmemory
  # Shared word tokenizer for keyword search and lexical scoring (BM25, MMR).
  # Centralizes the tokenization regex that was duplicated across the codebase.
  module Tokenizer
    module_function

    WORD = /\b[a-z0-9]{2,}\b/

    def tokenize(text)
      text.to_s.downcase.scan(WORD)
    end

    # Lexical match used by storage-level keyword search. A query is split into
    # tokens and matched as an OR of per-token substrings, so multi-word queries
    # work (a single contiguous substring of the whole query is no longer
    # required) while single-term/partial matches are preserved. An empty query
    # (no tokens) matches everything, keeping prior "return all" behavior.
    def matches?(text, query)
      tokens = tokenize(query)
      return true if tokens.empty?
      haystack = text.to_s.downcase
      tokens.any? { |t| haystack.include?(t) }
    end
  end
end
