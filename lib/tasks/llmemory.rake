# frozen_string_literal: true

namespace :llmemory do
  namespace :zero_mem do
    desc "Repair Zero-Mem trace watermarks vs checkpoint (requires trace_store configured in app)"
    task :repair, %i[user_id session_id] do |_t, args|
      require "llmemory"
      user_id = args[:user_id] || ENV["USER_ID"] || abort("USER_ID or user_id argument required")
      session_id = args[:session_id] || ENV["SESSION_ID"] || Llmemory::Memory::DEFAULT_SESSION_ID
      store = Llmemory::ZeroMem::Storages.build
      memory = Llmemory::Memory.new(user_id: user_id, session_id: session_id, trace_store: store,
                                   memory_mode: Llmemory.configuration.memory_mode)
      report = Llmemory::ZeroMem::Repair.new(storage: store).run!(
        user_id: user_id,
        session_id: session_id,
        checkpoint_messages: memory.messages
      )
      puts "Zero-Mem repair user_id=#{user_id} session_id=#{session_id}: #{report.inspect}"
    end

    desc "Reindex Zero-Mem traces for a user session (ENV: USER_ID, SESSION_ID)"
    task :reindex, %i[user_id session_id] do |_t, args|
      require "llmemory"
      user_id = args[:user_id] || ENV["USER_ID"] || abort("USER_ID or user_id argument required")
      session_id = args[:session_id] || ENV["SESSION_ID"] || Llmemory::Memory::DEFAULT_SESSION_ID
      store = Llmemory::ZeroMem::Storages.build
      memory = Llmemory::Memory.new(user_id: user_id, session_id: session_id, trace_store: store,
                                   memory_mode: Llmemory.configuration.memory_mode)
      status = memory.reindex_traces!(session_id: session_id)
      puts "Zero-Mem reindex: #{status.inspect}"
    end

    desc "Backfill checkpoint messages into traces (ENV: USER_ID, SESSION_ID)"
    task :backfill, %i[user_id session_id] do |_t, args|
      require "llmemory"
      user_id = args[:user_id] || ENV["USER_ID"] || abort("USER_ID required")
      session_id = args[:session_id] || ENV["SESSION_ID"] || Llmemory::Memory::DEFAULT_SESSION_ID
      store = Llmemory::ZeroMem::Storages.build
      memory = Llmemory::Memory.new(user_id: user_id, session_id: session_id, trace_store: store,
                                   memory_mode: Llmemory.configuration.memory_mode)
      report = Llmemory::ZeroMem::Backfill.new(storage: store).run!(
        user_id: user_id,
        session_id: session_id,
        messages: memory.messages
      )
      puts "Zero-Mem backfill: #{report.inspect}"
    end

    desc "Archive Zero-Mem traces past TTL (ENV: USER_ID, DRY_RUN=1)"
    task :expire, [:user_id] do |_t, args|
      require "llmemory"
      user_id = args[:user_id] || ENV["USER_ID"] || abort("USER_ID required")
      store = Llmemory::ZeroMem::Storages.build
      dry_run = ENV["DRY_RUN"].to_s == "1"
      report = Llmemory::Maintenance::ZeroMemTTL.new(storage: store).run!(user_id: user_id, dry_run: dry_run)
      puts "Zero-Mem expire: #{report.inspect}"
    end
  end
  desc "Backfill search_tokens blind index (and name_det on skills) for encrypted keyword search. " \
       "Env: FORCE=1 (re-backfill all rows), DRY_RUN=1 (count only), STORE=active_record|postgres"
  task :backfill_search_tokens, [:user_id] do |_t, args|
    Rake::Task[:environment].invoke if Rake::Task.task_defined?(:environment)

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

  desc "Archive long-term facts that the current consolidation policy would drop. " \
       "Env: DRY_RUN=1 (count only), USER_ID=..., LONG_TERM_TYPE=graph_based|file_based"
  task :prune_by_policy do
    Rake::Task[:environment].invoke if Rake::Task.task_defined?(:environment)

    require "llmemory"
    require_relative "../llmemory/maintenance/policy_prune"

    dry_run = ENV["DRY_RUN"].to_s == "1"
    user_id = ENV["USER_ID"].presence || "default"
    long_term_type = (ENV["LONG_TERM_TYPE"].presence || Llmemory.configuration.long_term_type).to_s

    memory = case long_term_type
    when "graph_based"
      Llmemory::LongTerm::GraphBased::Memory.new(user_id: user_id)
    when "file_based"
      Llmemory::LongTerm::FileBased::Memory.new(user_id: user_id)
    else
      abort "Unsupported LONG_TERM_TYPE=#{long_term_type.inspect}"
    end

    prune = Llmemory::Maintenance::PolicyPrune.new(dry_run: dry_run)
    result = prune.run(memory: memory)

    puts "Policy prune for user_id=#{user_id} type=#{long_term_type}" \
         "#{dry_run ? " [DRY RUN]" : ""}"
    puts "Archived: graph_edges=#{result.graph_edges} file_items=#{result.file_items} " \
         "(total=#{result.total})"
  end
end
