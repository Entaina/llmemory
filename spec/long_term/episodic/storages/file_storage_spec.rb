# frozen_string_literal: true

require "tmpdir"

RSpec.describe Llmemory::LongTerm::Episodic::Storages::FileStorage do
  let(:tmpdir) { Dir.mktmpdir("llmemory_episodic_file") }
  let(:storage) { described_class.new(base_path: tmpdir) }
  let(:user_id) { "user_1" }

  after { FileUtils.rm_rf(tmpdir) }

  def episode(summary:, action:, importance: 0.5)
    {
      summary: summary,
      outcome: "success",
      importance: importance,
      steps: [{ observation: "obs", action: action, result: "res" }],
      created_at: Time.now.iso8601(6)
    }
  end

  it "persists an episode to a JSON file and reads it back" do
    id = storage.save_episode(user_id, episode(summary: "Fixed bug", action: "patched"))
    expect(id).to start_with("ep_")
    expect(File).to exist(File.join(tmpdir, "user_1", "episodes", "#{id}.json"))
    loaded = storage.get_episode(user_id, id)
    expect(loaded[:summary]).to eq("Fixed bug")
    expect(loaded[:steps].first[:action]).to eq("patched")
  end

  it "survives a new storage instance (persistence)" do
    id = storage.save_episode(user_id, episode(summary: "Persistent", action: "saved"))
    fresh = described_class.new(base_path: tmpdir)
    expect(fresh.get_episode(user_id, id)[:summary]).to eq("Persistent")
  end

  it "searches episodes by text" do
    storage.save_episode(user_id, episode(summary: "Deploy rollback", action: "rolled back"))
    storage.save_episode(user_id, episode(summary: "Unrelated", action: "noop"))
    results = storage.search_episodes(user_id, "rollback")
    expect(results.size).to eq(1)
    expect(results.first[:summary]).to eq("Deploy rollback")
  end

  it "lists episodes newest first" do
    first = storage.save_episode(user_id, episode(summary: "first", action: "a"))
    second = storage.save_episode(user_id, episode(summary: "second", action: "b"))
    expect(storage.list_episodes(user_id).map { |e| e[:id] }).to eq([second, first])
  end

  it "counts episodes" do
    2.times { |i| storage.save_episode(user_id, episode(summary: "s#{i}", action: "a#{i}")) }
    expect(storage.count_episodes(user_id)).to eq(2)
  end
end
