# frozen_string_literal: true

require_relative "../entity_extractor"

module Llmemory
  module ZeroMem
    module Extractors
      class Heuristic < EntityExtractor
        CAP_PHRASE = /\b[\p{Lu}][\p{Ll}]+(?:\s+[\p{Lu}][\p{Ll}]+)*\b/u
        ALL_CAPS = /\b[\p{Lu}]{2,}\b/u

        def extract(text)
          normalized_text = Llmemory::Tokenizer.normalize(text)
          spans = []
          text.to_s.scan(CAP_PHRASE) { |m| spans << [Regexp.last_match.begin(0), m] }
          text.to_s.scan(ALL_CAPS) { |m| spans << [Regexp.last_match.begin(0), m] }

          spans.map do |start, raw|
            norm = normalize_key(raw)
            next if norm.length < 2

            {
              text: raw,
              normalized: norm,
              type: :entity,
              start: start,
              end: start + raw.length
            }
          end.compact.uniq { |h| h[:normalized] }
        end

        def name
          "heuristic"
        end

        private

        def normalize_key(raw)
          Llmemory::Tokenizer.normalize(raw).gsub(/\s+/, " ").strip
        end
      end
    end
  end
end
