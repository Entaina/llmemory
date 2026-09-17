# Zero-Mem storage and operations

Experimental Zero-Mem (`memory_mode: :zero_mem` or `:hybrid`) uses append-only traces and derived indexes.

## Stores

| Store | Config |
|-------|--------|
| `:memory` | Default for development |
| `:file` | `long_term_store: :file` or `zero_mem_trace_store: :file` |
| `:postgres` | Snapshot table + `DATABASE_URL` |
| `:active_record` | Rails app with `rails g llmemory:upgrade_zero_mem` |

File layout: `{long_term_storage_path}/zero_mem/snapshot.json` (encrypted when encryption is enabled).

Postgres layout: table `llmemory_zero_mem_snapshots` (global snapshot blob). Full relational parity for traces/units uses ActiveRecord migrations in `upgrade_zero_mem`.

## Upgrade

```bash
rails g llmemory:upgrade_zero_mem
rails db:migrate
```

## Rake

```bash
bundle exec rake llmemory:zero_mem:repair[user_id,session_id]
bundle exec rake llmemory:zero_mem:reindex[user_id,session_id]
bundle exec rake llmemory:zero_mem:backfill[user_id,session_id]
DRY_RUN=1 bundle exec rake llmemory:zero_mem:expire[user_id]
```

## Backfill

`backfill` creates traces from checkpoint messages still present in short-term storage. Text removed by prior LLM compaction cannot be reconstructed.

## Sidecar NER

Optional HTTP extractor (`zero_mem_entity_extractor: :http`) uses `SidecarClient` with timeouts and a circuit breaker. When the sidecar fails, indexing degrades to lexical/heuristic paths.
