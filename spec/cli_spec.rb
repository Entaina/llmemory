# frozen_string_literal: true

require "llmemory/cli"

RSpec.describe Llmemory::CLI do
  before do
    Llmemory.reset_configuration!
    Llmemory.configuration.short_term_store = :memory
    Llmemory.configuration.long_term_store = :memory
    Llmemory.configuration.long_term_type = :file_based
  end

  describe ".run" do
    it "prints help when no arguments" do
      out = StringIO.new
      allow($stdout).to receive(:puts) { |*args| out.puts(*args) }
      described_class.run([])
      expect(out.string).to include("llmemory - Inspect llmemory storage")
      expect(out.string).to include("users")
      expect(out.string).to include("short-term")
      expect(out.string).to include("stats")
    end

    it "prints help for --help" do
      out = StringIO.new
      allow($stdout).to receive(:puts) { |*args| out.puts(*args) }
      described_class.run(["--help"])
      expect(out.string).to include("llmemory - Inspect llmemory storage")
    end

    it "runs users command and prints no users when empty" do
      out = StringIO.new
      allow($stdout).to receive(:puts) { |*args| out.puts(*args) }
      described_class.run(["users"])
      expect(out.string).to include("No users with short-term memory found")
    end

    it "runs stats without user_id" do
      out = StringIO.new
      allow($stdout).to receive(:puts) { |*args| out.puts(*args) }
      described_class.run(["stats"])
      expect(out.string).to include("Total users")
    end

    it "runs short-term with --list-sessions" do
      out = StringIO.new
      allow($stdout).to receive(:puts) { |*args| out.puts(*args) }
      described_class.run(["short-term", "u1", "--list-sessions"])
      expect(out.string).to include("No sessions found for user u1")
    end

    it "exits with error for unknown command" do
      allow($stderr).to receive(:puts)
      expect { described_class.run(["unknown_cmd"]) }.to raise_error(SystemExit) do |e|
        expect(e.status).to eq(1)
      end
    end

    it "lists the new cognitive commands in help (SF10)" do
      out = StringIO.new
      allow($stdout).to receive(:puts) { |*args| out.puts(*args) }
      described_class.run([])
      expect(out.string).to include("episodes", "skills", "working", "forget-log")
    end

    it "runs the new episodes/skills/forget-log commands without crashing on empty state" do
      out = StringIO.new
      allow($stdout).to receive(:puts) { |*args| out.puts(*args) }
      described_class.run(["episodes", "u1"])
      described_class.run(["skills", "u1"])
      described_class.run(["forget-log", "u1"])
      expect(out.string).to include("No episodes for user u1")
      expect(out.string).to include("No skills for user u1")
      expect(out.string).to include("No forget audit entries for user u1")
    end
  end
end
