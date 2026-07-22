# frozen_string_literal: true

namespace :llmemory do
  desc "Backfill search_tokens blind index (and name_det on skills) for encrypted keyword search. " \
       "Env: FORCE=1 (re-backfill all rows), DRY_RUN=1 (count only), STORE=active_record|postgres"
  task :backfill_search_tokens, [:user_id] do |_t, args|
    require "llmemory"
    require_relative "../llmemory/maintenance/search_tokens_backfill"

    dry_run = ENV["DRY_RUN"].to_s == "1"
    force = ENV["FORCE"].to_s == "1"
    store = ENV["STORE"]&.to_sym

    if store.nil? && !Llmemory.configuration.encryption_enabled
      warn "Note: encryption_enabled is false; backfill still aligns schema but keyword search uses plaintext LIKE."
    end

    backfill = Llmemory::Maintenance::SearchTokensBackfill.new(
      dry_run: dry_run,
      force: force,
      store: store
    )

    user_id = args[:user_id].presence
    puts "Backfilling search_tokens#{user_id ? " for user_id=#{user_id}" : " (all users)"} " \
         "[store=#{store || Llmemory.configuration.long_term_store}]" \
         "#{dry_run ? " [DRY RUN]" : ""}#{force ? " [FORCE]" : ""}"

    result = backfill.run(user_id: user_id)
    summary = result.to_h

    puts "Updated: items=#{summary[:items]} resources=#{summary[:resources]} " \
         "episodes=#{summary[:episodes]} skills=#{summary[:skills]} " \
         "(total=#{summary[:total]})"
    puts "Dry run — no rows written." if dry_run
  end
end
