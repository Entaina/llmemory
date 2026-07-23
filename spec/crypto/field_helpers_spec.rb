# frozen_string_literal: true

require "spec_helper"

RSpec.describe Llmemory::Crypto::FieldHelpers do
  let(:helper_class) do
    Class.new do
      include Llmemory::Crypto::FieldHelpers

      def initialize(cipher)
        @cipher = cipher
      end
    end
  end

  after { Llmemory.reset_configuration! }

  describe "#search_tokens_for" do
    it "returns space-delimited blind-index digests when encryption is enabled" do
      cipher = Llmemory::Crypto::Cipher.new("test-key")
      helper = helper_class.new(cipher)

      tokens = helper.send(:search_tokens_for, "User prefers Ruby")
      expect(tokens).to start_with(" ")
      expect(tokens).to end_with(" ")
      expect(tokens.split.size).to eq(3)
    end

    it "returns plaintext tokens when encryption is disabled" do
      helper = helper_class.new(Llmemory::Crypto::NullCipher.new)

      tokens = helper.send(:search_tokens_for, "User prefers Ruby")
      expect(tokens).to include(" user prefers ruby ")
    end
  end

  describe "#deserialize_state" do
    it "raises DecryptionError when ciphertext is read with encryption disabled" do
      cipher = Llmemory::Crypto::Cipher.new("test-key")
      encrypted = cipher.encrypt('{"messages":[]}')
      helper = helper_class.new(Llmemory::Crypto::NullCipher.new)

      expect { helper.send(:deserialize_state, encrypted) }
        .to raise_error(Llmemory::Crypto::DecryptionError, /encryption is disabled/)
    end
  end
end
