# frozen_string_literal: true

require "spec_helper"

RSpec.describe Llmemory::Maintenance::SearchTokensBackfill do
  let(:cipher) { Llmemory::Crypto::Cipher.new("backfill-test-key") }
  let(:backfill) { described_class.new(store: :postgres, cipher: cipher) }

  after { Llmemory.reset_configuration! }

  it "raises for unsupported stores" do
    expect {
      described_class.new(store: :file).run
    }.to raise_error(Llmemory::ConfigurationError, /active_record or :postgres/)
  end

  describe "postgres backend" do
    let(:conn) { double("PG::Connection") }
    let(:result_rows) { [] }

    before do
      allow(backfill).to receive(:pg_conn).and_return(conn)
      allow(backfill).to receive(:pg_column_exists?).and_return(true)
      allow(conn).to receive(:exec_params) do |sql, _params|
        if sql.start_with?("SELECT")
          result_rows
        else
          double(cmd_tuples: 1)
        end
      end
    end

    it "updates search_tokens for items from decrypted content" do
      encrypted = cipher.encrypt("User prefers Ruby")
      result_rows.replace([{ "id" => "item_1", "user_id" => "u1", "content" => encrypted }])

      expect(conn).to receive(:exec_params).with(
        "UPDATE llmemory_items SET search_tokens = $1 WHERE id = $2",
        [kind_of(String), "item_1"]
      )

      result = backfill.run(user_id: "u1")
      expect(result.items).to eq(1)
      expect(result.total).to eq(1)
    end

    it "does not write when dry_run is true" do
      encrypted = cipher.encrypt("User prefers Ruby")
      result_rows.replace([{ "id" => "item_1", "user_id" => "u1", "content" => encrypted }])
      dry = described_class.new(store: :postgres, cipher: cipher, dry_run: true)
      allow(dry).to receive(:pg_conn).and_return(conn)
      allow(dry).to receive(:pg_column_exists?).and_return(true)

      expect(conn).not_to receive(:exec_params).with(/UPDATE/, anything)

      result = dry.run(user_id: "u1")
      expect(result.items).to eq(1)
      expect(result.dry_run).to be true
    end

    it "backfills name_det on skills from decrypted data" do
      data = cipher.encrypt_json({ name: "deploy_skill", description: "Deploy app" })
      result_rows.replace([
        { "id" => "skill_1", "user_id" => "u1", "data" => data, "search_text" => cipher.encrypt("deploy app") }
      ])

      expect(conn).to receive(:exec_params).with(
        /UPDATE llmemory_skills SET search_tokens = \$1, name_det = \$2 WHERE id = \$3/,
        array_including(kind_of(String), kind_of(String), "skill_1")
      )

      result = backfill.run(user_id: "u1")
      expect(result.skills).to eq(1)
    end
  end
end
