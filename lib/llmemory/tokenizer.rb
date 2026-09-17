# frozen_string_literal: true

module Llmemory
  # Shared word tokenizer for keyword search and lexical scoring (BM25, MMR).
  # Unicode-aware (NFKC, accented letters, CJK, digits).
  module Tokenizer
    module_function

    # Latin letters (2+), single Han ideographs, digit runs.
    TOKEN_PATTERN = /\d+|\p{Han}+|[\p{L}&&[^\p{Han}]]{2,}/u

    def normalize(text)
      str = text.to_s
      unless str.encoding == Encoding::UTF_8 && str.valid_encoding?
        str = str.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
      end
      str.unicode_normalize(:nfkc).downcase
    end

    def tokenize(text)
      normalized = normalize(text)
      return [] if normalized.strip.empty?

      normalized.scan(TOKEN_PATTERN)
    end

    # Lexical match used by storage-level keyword search. A query is split into
    # tokens and matched as an OR of per-token substrings.
    def matches?(text, query)
      tokens = tokenize(query)
      return true if tokens.empty?

      haystack = normalize(text)
      tokens.any? { |t| haystack.include?(t) }
    end
  end
end
