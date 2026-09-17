# frozen_string_literal: true

RSpec.describe "llmemory zero_mem rake tasks" do
  it "defines repair, reindex, backfill, and expire tasks" do
    load File.expand_path("../../lib/tasks/llmemory.rake", __dir__)
    expect(Rake::Task.task_defined?("llmemory:zero_mem:repair")).to be(true)
    expect(Rake::Task.task_defined?("llmemory:zero_mem:reindex")).to be(true)
    expect(Rake::Task.task_defined?("llmemory:zero_mem:backfill")).to be(true)
    expect(Rake::Task.task_defined?("llmemory:zero_mem:expire")).to be(true)
  end
end
