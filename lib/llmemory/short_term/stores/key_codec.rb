# frozen_string_literal: true

module Llmemory
  module ShortTerm
    module Stores
      # Escapes user/session identifiers so composite keys remain unambiguous
      # when ids contain the separator character `:`.
      module KeyCodec
        ESCAPE = "%3A"
        SEPARATOR = ":"

        module_function

        def encode(value)
          value.to_s.gsub("%", "%25").gsub(SEPARATOR, ESCAPE)
        end

        def decode(value)
          value.to_s.gsub(ESCAPE, SEPARATOR).gsub("%25", "%")
        end

        def composite_key(*parts)
          parts.map { |part| encode(part) }.join(SEPARATOR)
        end

        def split_composite_key(key, parts: 2)
          encoded = key.to_s.split(SEPARATOR, parts)
          encoded.map { |part| decode(part) }
        end
      end
    end
  end
end
