# frozen_string_literal: true

require "rake"
require "spec_helper"

RSpec.describe "llmemory:backfill_search_tokens" do
  let(:rake) { Rake::Application.new }
  let(:task_name) { "llmemory:backfill_search_tokens" }
  let(:rakefile) { File.expand_path("../../lib/tasks/llmemory.rake", __dir__) }

  let(:backfill_result) do
    Llmemory::Maintenance::SearchTokensBackfill::Result.new(
      items: 0, resources: 0, episodes: 0, skills: 0, skipped: 0, dry_run: false
    )
  end

  let(:backfill) do
    instance_double(Llmemory::Maintenance::SearchTokensBackfill, run: backfill_result)
  end

  before do
    Rake.application = rake
    load rakefile
    stub_presence!
    allow(Llmemory::Maintenance::SearchTokensBackfill).to receive(:new).and_return(backfill)
  end

  after do
    Rake.application = nil
  end

  def stub_presence!
    NilClass.class_eval { def presence; nil; end unless method_defined?(:presence) }
    String.class_eval { def presence; empty? ? nil : self; end unless method_defined?(:presence) }
  end

  it "invokes :environment when it is defined after the rake file loads" do
    invoked = false
    Rake::Task.define_task(:environment) { invoked = true }

    rake[task_name].invoke

    expect(invoked).to be(true)
    expect(backfill).to have_received(:run).with(user_id: nil)
  end

  it "runs without :environment when that task is not defined" do
    expect { rake[task_name].invoke }.not_to raise_error
    expect(backfill).to have_received(:run).with(user_id: nil)
  end
end
