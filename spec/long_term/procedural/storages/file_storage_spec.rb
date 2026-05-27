# frozen_string_literal: true

require "tmpdir"

RSpec.describe Llmemory::LongTerm::Procedural::Storages::FileStorage do
  let(:tmpdir) { Dir.mktmpdir("llmemory_procedural_file") }
  let(:storage) { described_class.new(base_path: tmpdir) }
  let(:user_id) { "user_1" }

  after { FileUtils.rm_rf(tmpdir) }

  def skill(name:, body:, **rest)
    { name: name, body: body, description: rest[:description], kind: rest[:kind] || "prompt",
      version: rest[:version] || 1, success_count: 0, failure_count: 0, created_at: Time.now.iso8601(6) }
  end

  it "persists a skill to a JSON file and reads it back" do
    id = storage.save_skill(user_id, skill(name: "rollback", body: "kubectl rollout undo"))
    expect(id).to start_with("skill_")
    expect(File).to exist(File.join(tmpdir, "user_1", "skills", "#{id}.json"))
    expect(storage.get_skill(user_id, id)[:body]).to eq("kubectl rollout undo")
  end

  it "survives a new storage instance (persistence)" do
    id = storage.save_skill(user_id, skill(name: "persist", body: "stays"))
    fresh = described_class.new(base_path: tmpdir)
    expect(fresh.get_skill(user_id, id)[:name]).to eq("persist")
  end

  it "searches skills by text" do
    storage.save_skill(user_id, skill(name: "rollback", description: "revert deploy", body: "undo"))
    storage.save_skill(user_id, skill(name: "unrelated", body: "noop"))
    results = storage.search_skills(user_id, "revert")
    expect(results.map { |s| s[:name] }).to eq(["rollback"])
  end

  it "finds skills by name" do
    storage.save_skill(user_id, skill(name: "rollback", body: "v1", version: 1))
    storage.save_skill(user_id, skill(name: "rollback", body: "v2", version: 2))
    expect(storage.find_skills_by_name(user_id, "rollback").size).to eq(2)
  end

  it "records outcomes and persists them across instances" do
    id = storage.save_skill(user_id, skill(name: "rollback", body: "x"))
    storage.record_outcome(user_id, id, success: true)
    storage.record_outcome(user_id, id, success: false)
    fresh = described_class.new(base_path: tmpdir)
    reloaded = fresh.get_skill(user_id, id)
    expect(reloaded[:success_count]).to eq(1)
    expect(reloaded[:failure_count]).to eq(1)
  end
end
