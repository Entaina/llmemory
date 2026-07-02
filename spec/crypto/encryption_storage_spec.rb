# frozen_string_literal: true

require "tmpdir"
require "spec_helper"

RSpec.describe "encrypted storage" do
  let(:cipher) { Llmemory::Crypto::Cipher.new("storage-test-key") }
  let(:user_id) { "user_enc" }

  after { Llmemory.reset_configuration! }

  describe Llmemory::ShortTerm::Stores::RedisStore do
    let(:store) { described_class.new(cipher: cipher) }

    it "encrypts and decrypts checkpoint state" do
      state = { messages: [{ role: :user, content: "secret message" }] }
      serialized = store.send(:serialize, state)
      expect(serialized).not_to include("secret message")
      expect(serialized).to include("enc:v1:")

      restored = store.send(:deserialize, serialized)
      expect(restored[:messages].first[:content]).to eq("secret message")
    end
  end

  describe "storage isolation between keys" do
    let(:tmpdir) { Dir.mktmpdir("llmemory_enc_lt") }

    after { FileUtils.rm_rf(tmpdir) }

    it "cannot decrypt data written under a different key" do
      storage_a = Llmemory::LongTerm::FileBased::Storages::FileStorage.new(
        base_path: tmpdir,
        cipher: Llmemory::Crypto::Cipher.new("key-alpha")
      )
      storage_a.save_item(
        user_id,
        category: "facts",
        content: "Alpha-only knowledge",
        source_resource_id: "r1"
      )

      storage_b = Llmemory::LongTerm::FileBased::Storages::FileStorage.new(
        base_path: tmpdir,
        cipher: Llmemory::Crypto::Cipher.new("key-beta")
      )
      expect { storage_b.get_all_items(user_id) }.to raise_error(Llmemory::Crypto::DecryptionError)
    end
  end

  describe Llmemory::LongTerm::FileBased::Storages::FileStorage do
    let(:tmpdir) { Dir.mktmpdir("llmemory_enc_fb") }
    let(:storage) { described_class.new(base_path: tmpdir, cipher: cipher) }

    after { FileUtils.rm_rf(tmpdir) }

    it "persists encrypted resources and items" do
      storage.save_resource(user_id, "confidential resource")
      storage.save_item(
        user_id,
        category: "work",
        content: "confidential fact",
        source_resource_id: "r1"
      )

      item_path = Dir.glob(File.join(tmpdir, "**", "items", "*.json")).first
      expect(File.read(item_path)).not_to include("confidential fact")
      expect(File.read(item_path)).to include("enc:v1:")

      items = storage.get_all_items(user_id)
      expect(items.first[:content]).to eq("confidential fact")
    end

    it "persists encrypted categories" do
      storage.save_category(user_id, "profile", "Private profile data")
      path = Dir.glob(File.join(tmpdir, "**", "categories", "*.md")).first
      expect(File.read(path)).not_to include("Private profile")
      expect(storage.load_category(user_id, "profile")).to eq("Private profile data")
    end
  end

  describe Llmemory::LongTerm::Episodic::Storages::FileStorage do
    let(:tmpdir) { Dir.mktmpdir("llmemory_enc_ep") }
    let(:storage) { described_class.new(base_path: tmpdir, cipher: cipher) }

    after { FileUtils.rm_rf(tmpdir) }

    it "encrypts episode files and supports keyword search after decrypt" do
      storage.save_episode(user_id, {
        summary: "Deployed the payment service",
        outcome: "success",
        steps: [{ observation: "API ready", action: "deploy", result: "ok" }]
      })

      path = Dir.glob(File.join(tmpdir, "**", "episodes", "*.json")).first
      expect(File.read(path)).not_to include("payment service")
      results = storage.search_episodes(user_id, "payment")
      expect(results).not_to be_empty
    end
  end

  describe Llmemory::LongTerm::GraphBased::Storages::MemoryStorage do
    let(:storage) { Llmemory::LongTerm::GraphBased::Storages::MemoryStorage.new }

    it "find_node_by_name works without encryption (in-memory backend)" do
      node = Llmemory::LongTerm::GraphBased::Node.new(
        id: "n1", user_id: user_id, entity_type: "person", name: "Alice", properties: {}
      )
      storage.save_node(user_id, node)
      found = storage.find_node_by_name(user_id, "person", "Alice")
      expect(found.name).to eq("Alice")
    end
  end
end
