# frozen_string_literal: true

RSpec.describe "forget(mode:)" do
  describe Llmemory::LongTerm::Episodic::Memory do
    let(:memory) { described_class.new(user_id: "u1") }

    it ":soft archives — hidden from list/search but still accessible by id" do
      id = memory.write(steps: [{ observation: "deploy failed", action: "rolled back" }], outcome: "recovered")
      expect(memory.count).to eq(1)

      removed = memory.forget(ids: [id], mode: :soft, reason: "noisy")
      expect(removed).to eq(1)
      expect(memory.count).to eq(0)
      expect(memory.list).to be_empty
      expect(memory.search_candidates("rolled")).to be_empty
      expect(memory.find_episode(id)).not_to be_nil
    end

    it ":hard physically deletes — gone from get_episode" do
      id = memory.write(steps: [{ observation: "x", action: "y" }])
      memory.forget(ids: [id], mode: :hard)
      expect(memory.find_episode(id)).to be_nil
    end

    it "defaults to :soft" do
      id = memory.write(steps: [{ observation: "x", action: "y" }])
      memory.forget(ids: [id])
      expect(memory.find_episode(id)).not_to be_nil
    end
  end

  describe Llmemory::LongTerm::Procedural::Memory do
    let(:memory) { described_class.new(user_id: "u1") }

    it ":soft archives — hidden from list/search but accessible by id" do
      id = memory.write(name: "rollback", body: "kubectl rollout undo")
      expect(memory.count).to eq(1)

      memory.forget(ids: [id], mode: :soft)
      expect(memory.count).to eq(0)
      expect(memory.list).to be_empty
      expect(memory.find_skill("rollback")).to be_nil
      expect(memory.get_skill(id)).not_to be_nil
    end

    it ":hard physically deletes" do
      id = memory.write(name: "rollback", body: "kubectl rollout undo")
      memory.forget(ids: [id], mode: :hard)
      expect(memory.get_skill(id)).to be_nil
    end
  end
end

RSpec.describe Llmemory::Maintenance::TTLExpiry do
  let(:user_id) { "u_ttl" }
  let(:episodic) { Llmemory::LongTerm::Episodic::Memory.new(user_id: user_id) }
  let(:procedural) { Llmemory::LongTerm::Procedural::Memory.new(user_id: user_id) }

  it "soft-archives episodes older than ttl_episodic_days" do
    Llmemory.configuration.ttl_episodic_days = 7
    Llmemory.configuration.ttl_procedural_days = nil

    old_id = episodic.write(steps: [{ observation: "old" }], outcome: "long ago")
    # Backdate the stored episode beyond the TTL window.
    storage = episodic.instance_variable_get(:@storage)
    storage.instance_variable_get(:@episodes)[user_id].each { |e| e[:created_at] = Time.now - (30 * 86400) }

    fresh_id = episodic.write(steps: [{ observation: "new" }], outcome: "now")
    expect(episodic.count).to eq(2)

    result = described_class.run!(user_id, episodic: episodic, procedural: procedural)

    expect(result[:episodic]).to eq(1)
    expect(result[:procedural]).to eq(0)
    expect(episodic.count).to eq(1)
    expect(episodic.find_episode(old_id)).not_to be_nil  # still accessible
    expect(episodic.find_episode(fresh_id)).not_to be_nil
  ensure
    Llmemory.configuration.ttl_episodic_days = nil
  end

  it "is a no-op when no TTL is configured" do
    Llmemory.configuration.ttl_episodic_days = nil
    Llmemory.configuration.ttl_procedural_days = nil

    episodic.write(steps: [{ observation: "x" }])
    result = described_class.run!(user_id, episodic: episodic, procedural: procedural)
    expect(result).to eq(episodic: 0, procedural: 0)
  end
end
