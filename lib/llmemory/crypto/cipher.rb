# frozen_string_literal: true

require "openssl"
require "json"

module Llmemory
  module Crypto
    class DecryptionError < Llmemory::Error; end

    # No-op cipher when encryption is disabled or no key is configured.
    class NullCipher
      def enabled?
        false
      end

      def encrypt(str)
        str.to_s
      end

      def encrypt_deterministic(str)
        str.to_s
      end

      def decrypt(str)
        str.to_s
      end

      def encrypt_json(obj)
        JSON.generate(obj)
      end

      def decrypt_json(str)
        JSON.parse(str.to_s, symbolize_names: true)
      end

      def encrypted?(str)
        false
      end

      def blind_index(token)
        token.to_s.downcase
      end
    end

    # AES-256-GCM encryption with separate content (random IV) and index
    # (deterministic IV) subkeys derived from the master key via HMAC-SHA256.
    class Cipher
      MARKER = "enc:v1:"
      DETERMINISTIC_MARKER = "encd:v1:"
      IV_LENGTH = 12
      TAG_LENGTH = 16

      def initialize(key)
        @master_key = derive_master_key(key)
        @content_key = derive_subkey("content")
        @index_key = derive_subkey("index")
      end

      def enabled?
        true
      end

      def encrypt(plaintext)
        str = plaintext.to_s
        return str if str.empty?

        encrypt_with_key(str, @content_key, iv: OpenSSL::Random.random_bytes(IV_LENGTH), marker: MARKER)
      end

      def encrypt_deterministic(plaintext)
        str = plaintext.to_s
        return str if str.empty?

        iv = OpenSSL::HMAC.digest("SHA256", @index_key, str)[0, IV_LENGTH]
        encrypt_with_key(str, @index_key, iv: iv, marker: DETERMINISTIC_MARKER)
      end

      def decrypt(ciphertext)
        str = ciphertext.to_s
        return str if str.empty?
        return str unless encrypted?(str)

        marker, key = if str.start_with?(DETERMINISTIC_MARKER)
          [DETERMINISTIC_MARKER, @index_key]
        else
          [MARKER, @content_key]
        end

        payload = decode64(str.delete_prefix(marker))
        iv = payload[0, IV_LENGTH]
        tag = payload[IV_LENGTH, TAG_LENGTH]
        ct = payload[(IV_LENGTH + TAG_LENGTH)..]

        cipher = OpenSSL::Cipher.new("aes-256-gcm")
        cipher.decrypt
        cipher.key = key
        cipher.iv = iv
        cipher.auth_tag = tag
        cipher.auth_data = ""
        cipher.update(ct) + cipher.final
      rescue OpenSSL::Cipher::CipherError, ArgumentError => e
        raise DecryptionError, "Failed to decrypt data: #{e.message}"
      end

      def encrypt_json(obj)
        encrypt(JSON.generate(obj))
      end

      def decrypt_json(str)
        JSON.parse(decrypt(str), symbolize_names: true)
      end

      def encrypted?(str)
        s = str.to_s
        s.start_with?(MARKER) || s.start_with?(DETERMINISTIC_MARKER)
      end

      # Deterministic HMAC digest for blind-index keyword search over encrypted fields.
      def blind_index(token)
        str = token.to_s.downcase
        return str if str.empty?

        OpenSSL::HMAC.hexdigest("SHA256", @index_key, str)[0, 32]
      end

      private

      def encrypt_with_key(plaintext, key, iv:, marker:)
        cipher = OpenSSL::Cipher.new("aes-256-gcm")
        cipher.encrypt
        cipher.key = key
        cipher.iv = iv
        cipher.auth_data = ""
        ct = cipher.update(plaintext) + cipher.final
        tag = cipher.auth_tag
        marker + encode64(iv + tag + ct)
      end

      def encode64(bin)
        [bin].pack("m0")
      end

      def decode64(str)
        str.unpack1("m0")
      end

      def derive_master_key(key)
        raw = key.to_s
        raise ConfigurationError, "encryption_key cannot be empty when encryption is enabled" if raw.empty?

        OpenSSL::Digest::SHA256.digest(raw)
      end

      def derive_subkey(label)
        OpenSSL::HMAC.digest("SHA256", @master_key, "llmemory:#{label}")[0, 32]
      end
    end
  end
end
