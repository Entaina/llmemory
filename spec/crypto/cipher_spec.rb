# frozen_string_literal: true

require "spec_helper"

RSpec.describe Llmemory::Crypto::Cipher do
  let(:key) { "test-secret-key" }
  subject(:cipher) { described_class.new(key) }

  describe "#encrypt / #decrypt" do
    it "round-trips plaintext" do
      original = "User prefers Ruby over Python"
      expect(cipher.decrypt(cipher.encrypt(original))).to eq(original)
    end

    it "produces different ciphertext for the same plaintext (non-deterministic)" do
      a = cipher.encrypt("same text")
      b = cipher.encrypt("same text")
      expect(a).not_to eq(b)
      expect(cipher.decrypt(a)).to eq("same text")
      expect(cipher.decrypt(b)).to eq("same text")
    end

    it "passes through unmarked strings on decrypt" do
      expect(cipher.decrypt("plain legacy data")).to eq("plain legacy data")
    end

    it "raises DecryptionError with wrong key" do
      encrypted = cipher.encrypt("secret")
      other = described_class.new("wrong-key")
      expect { other.decrypt(encrypted) }.to raise_error(Llmemory::Crypto::DecryptionError)
    end

    it "raises DecryptionError when ciphertext is tampered" do
      encrypted = cipher.encrypt("secret")
      tampered = encrypted.sub(/.$/, "X")
      expect { cipher.decrypt(tampered) }.to raise_error(Llmemory::Crypto::DecryptionError)
    end
  end

  describe "#encrypt_deterministic" do
    it "is stable for the same input" do
      a = cipher.encrypt_deterministic("Alice")
      b = cipher.encrypt_deterministic("Alice")
      expect(a).to eq(b)
      expect(cipher.decrypt(a)).to eq("Alice")
    end

    it "uses a distinct marker from non-deterministic encryption" do
      expect(cipher.encrypt_deterministic("x")).to start_with(Llmemory::Crypto::Cipher::DETERMINISTIC_MARKER)
      expect(cipher.encrypt("x")).to start_with(Llmemory::Crypto::Cipher::MARKER)
    end
  end

  describe "#encrypt_json / #decrypt_json" do
    it "round-trips hashes" do
      data = { role: "user", content: "hello", nested: { a: 1 } }
      encrypted = cipher.encrypt_json(data)
      expect(cipher.decrypt_json(encrypted)).to eq(data)
    end
  end
end

RSpec.describe Llmemory::Crypto::NullCipher do
  subject(:cipher) { described_class.new }

  it "passes values through unchanged" do
    expect(cipher.encrypt("hello")).to eq("hello")
    expect(cipher.decrypt("hello")).to eq("hello")
    expect(cipher.enabled?).to be false
  end
end

RSpec.describe Llmemory do
  describe ".build_cipher" do
    after { Llmemory.reset_configuration! }

    it "returns NullCipher when encryption is disabled" do
      expect(Llmemory.build_cipher).not_to be_enabled
    end

    it "returns Cipher when encryption is enabled with a config key" do
      Llmemory.configure do |c|
        c.encryption_enabled = true
        c.encryption_key = "global-key"
      end
      expect(Llmemory.build_cipher).to be_enabled
    end

    it "uses an explicit instance key even when global flag is off" do
      expect(Llmemory.build_cipher("instance-key")).to be_enabled
    end
  end
end
