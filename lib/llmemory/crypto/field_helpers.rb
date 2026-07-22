# frozen_string_literal: true

require "json"

module Llmemory
  module Crypto
    # Shared encrypt/decrypt helpers for storage backends.
    module FieldHelpers
      private

      def cipher
        @cipher || Llmemory.build_cipher
      end

      def enc(str)
        return str if str.nil?
        return str.to_s unless cipher.enabled?

        cipher.encrypt(str.to_s)
      end

      def dec(str)
        return str if str.nil?
        return str unless str.is_a?(String) && cipher.encrypted?(str)

        cipher.decrypt(str)
      end

      def enc_det(str)
        return str if str.nil?
        return str.to_s unless cipher.enabled?

        cipher.encrypt_deterministic(str.to_s)
      end

      def enc_json(obj)
        return obj if obj.nil?
        return obj unless cipher.enabled?

        cipher.encrypt_json(obj)
      end

      def dec_json(value)
        return value if value.nil?
        return value.transform_keys(&:to_sym) if value.is_a?(Hash)
        return value unless value.is_a?(String) && cipher.encrypted?(value)

        cipher.decrypt_json(value)
      end

      def write_encrypted_file(path, data)
        payload = JSON.generate(data)
        File.write(path, cipher.enabled? ? cipher.encrypt(payload) : payload)
      end

      def read_encrypted_file(path)
        raw = File.read(path)
        json = cipher.enabled? && cipher.encrypted?(raw) ? cipher.decrypt(raw) : raw
        JSON.parse(json, symbolize_names: true)
      end

      def write_encrypted_text_file(path, content, append: false)
        text = content.to_s
        if cipher.enabled?
          if append && File.file?(path)
            existing = read_encrypted_text_file(path)
            text = existing + text
          end
          File.write(path, cipher.encrypt(text))
        elsif append && File.file?(path)
          File.write(path, File.read(path) + text)
        else
          File.write(path, text)
        end
      end

      def read_encrypted_text_file(path)
        raw = File.read(path)
        cipher.enabled? && cipher.encrypted?(raw) ? cipher.decrypt(raw) : raw
      end

      def serialize_state(state)
        json = JSON.generate(state)
        return json unless cipher.enabled?

        cipher.encrypt(json)
      end

      def deserialize_state(data)
        if data.is_a?(Hash)
          return data.transform_keys(&:to_sym)
        end

        str = data.to_s
        json = cipher.enabled? && cipher.encrypted?(str) ? cipher.decrypt(str) : str
        JSON.parse(json, symbolize_names: true)
      end

      def parse_provenance(value)
        return nil if value.nil?
        return value.transform_keys(&:to_sym) if value.is_a?(Hash)
        return dec_json(value) if value.is_a?(String) && cipher.encrypted?(value)

        JSON.parse(value.to_s, symbolize_names: true)
      rescue JSON::ParserError
        nil
      end

      # Space-delimited blind-index digests for encrypted keyword search.
      def search_tokens_for(text)
        tokens = Llmemory::Tokenizer.tokenize(text).uniq
        return nil if tokens.empty?

        digests = tokens.map { |t| cipher.blind_index(t) }
        " #{digests.join(' ')} "
      end

      # OR-of-token SQL filter. Uses blind index on `search_tokens_column` when
      # encryption is enabled; otherwise LIKE on the plaintext `column`.
      def blind_token_filter(column, query, start_index, search_tokens_column: nil)
        tokens = Llmemory::Tokenizer.tokenize(query)
        return ["", []] if tokens.empty?

        if cipher.enabled? && search_tokens_column
          digests = tokens.map { |t| cipher.blind_index(t) }
          likes = digests.each_index.map { |i| "#{search_tokens_column} LIKE $#{start_index + i}" }
          [" AND (#{likes.join(' OR ')})", digests.map { |d| "% #{d} %" }]
        else
          likes = tokens.each_index.map { |i| "LOWER(#{column}) LIKE $#{start_index + i}" }
          [" AND (#{likes.join(' OR ')})", tokens.map { |t| "%#{t}%" }]
        end
      end
    end
  end
end
