# frozen_string_literal: true

module Llmemory
  # Shared word tokenizer for keyword search and lexical scoring (BM25, MMR).
  # Unicode-aware (NFKC, accented letters, CJK, digits).
  module Tokenizer
    module_function

    # Latin letters (2+), single Han ideographs, digit runs.
    TOKEN_PATTERN = /\d+|\p{Han}+|[\p{L}&&[^\p{Han}]]{2,}/u

    STOPWORDS = %w[
      a an the and or but if in on at to for of is are was were be been being
      do does did have has had what when where which who whom how why this that
      these those with from as by about into through during cuál cual qué que
      cómo como cuándo cuando dónde donde
    ].freeze

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

    # Light lemma for lexical retrieval: plurals and a few verb forms.
    def stem(token)
      t = token.to_s.downcase
      return "ride" if t == "rode" || t == "riding"
      return t if t.length <= 4 || t.end_with?("ss")
      return t.sub(/ies\z/, "y") if t.end_with?("ies")

      t.end_with?("s") ? t.sub(/s\z/, "") : t
    end

    # Lexical match used by storage-level keyword search. A query is split into
    # tokens and matched as an OR of per-token substrings.
    def content_tokens(text)
      tokenize(text).reject { |t| STOPWORDS.include?(t) }
    end

    def matches?(text, query)
      tokens = content_tokens(query)
      return true if tokens.empty?

      haystack = normalize(text)
      tokens.any? { |t| haystack.include?(t) }
    end
  end
end
