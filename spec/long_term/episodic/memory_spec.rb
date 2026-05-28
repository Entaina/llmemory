# frozen_string_literal: true

RSpec.describe Llmemory::LongTerm::Episodic::Memory do
  let(:user_id) { "user_1" }
  let(:memory) { described_class.new(user_id: user_id) }

  describe "#record_episode" do
    it "returns an episode id" do
      id = memory.record_episode(steps: [{ action: "did a thing" }])
      expect(id).to start_with("ep_")
    end

    it "derives a summary from steps when none is given" do
      id = memory.record_episode(steps: [{ action: "retried" }, { action: "succeeded" }])
      ep = memory.find_episode(id)
      expect(ep.summary).to include("retried -> succeeded")
    end

    it "keeps a caller-provided summary" do
      id = memory.record_episode(steps: [{ action: "x" }], summary: "Custom summary")
      expect(memory.find_episode(id).summary).to eq("Custom summary")
    end

    it "stamps provenance recording how the episode was produced" do
      id = memory.record_episode(steps: [{ observation: "saw error", action: "fixed it" }], importance: 0.8)
      prov = memory.find_episode(id).provenance
      expect(prov[:method]).to eq("episode_recording")
      expect(prov[:confidence]).to eq(0.8)
      expect(prov[:sources].first[:type]).to eq("text_sha256")
    end
  end

  describe "#recent_episodes" do
    it "returns episodes newest first" do
      first = memory.record_episode(steps: [{ action: "first" }])
      second = memory.record_episode(steps: [{ action: "second" }])
      recent = memory.recent_episodes(limit: 2)
      expect(recent.map(&:id)).to eq([second, first])
    end

    it "respects the limit" do
      3.times { |i| memory.record_episode(steps: [{ action: "step#{i}" }]) }
      expect(memory.recent_episodes(limit: 2).size).to eq(2)
    end
  end

  describe "#count" do
    it "counts recorded episodes" do
      2.times { memory.record_episode(steps: [{ action: "a" }]) }
      expect(memory.count).to eq(2)
    end
  end

  describe "#forget" do
    it "removes episodes by id and audits the removal" do
      keep = memory.record_episode(steps: [{ action: "keep" }])
      drop = memory.record_episode(steps: [{ action: "drop" }])

      removed = memory.forget(ids: [drop, "ghost"], reason: "obsolete")

      expect(removed).to eq(1)
      expect(memory.recent_episodes.map(&:id)).to eq([keep])
      entry = memory.forget_log.entries(user_id).last
      expect(entry[:memory_type]).to eq("episodic")
      expect(entry[:ids]).to eq([drop])
      expect(entry[:reason]).to eq("obsolete")
    end
  end

  describe "#search_candidates" do
    before do
      memory.record_episode(
        steps: [{ observation: "deploy failed", action: "rolled back" }],
        outcome: "recovered", importance: 0.7
      )
    end

    it "returns retrieval-compatible candidates carrying importance and provenance" do
      candidates = memory.search_candidates("rolled back")
      expect(candidates).not_to be_empty
      c = candidates.first
      expect(c).to include(:text, :timestamp, :score, :importance, :provenance)
      expect(c[:score]).to eq(1.0)
      expect(c[:importance]).to eq(0.7)
      expect(c[:provenance][:method]).to eq("episode_recording")
    end

    it "isolates by user_id" do
      expect(memory.search_candidates("rolled back", user_id: "other")).to eq([])
    end

    it "matches a multi-word query whose terms are non-contiguous in the text" do
      # episode text contains "deploy failed" and "rolled back" separately
      results = memory.search_candidates("deploy rolled")
      expect(results).not_to be_empty
    end
  end

  describe "hybrid retrieval with a vector store (SF2)" do
    let(:vector_store) do
      stored = []
      double("VectorStore").tap do |d|
        allow(d).to receive(:embed).and_return([0.1, 0.2, 0.3])
        allow(d).to receive(:store) { |id:, **_| stored << id; id }
        allow(d).to receive(:search_by_text) { |_q, **_| stored.map { |id| { id: id, score: 0.9 } } }
      end
    end
    let(:memory) { described_class.new(user_id: user_id, vector_store: vector_store) }

    it "embeds and stores the episode on record" do
      id = memory.record_episode(steps: [{ observation: "deploy failed", action: "rolled back" }])
      expect(vector_store).to have_received(:embed)
      expect(vector_store).to have_received(:store)
      expect(id).to start_with("ep_")
    end

    it "returns vector hits even when the keyword query does not match" do
      id = memory.record_episode(steps: [{ observation: "deploy failed", action: "rolled back" }])
      results = memory.search_candidates("totally unrelated phrasing")
      expect(results.map { |c| c[:id] }).to include(id)
    end
  end
end
