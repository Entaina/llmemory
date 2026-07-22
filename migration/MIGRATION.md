# Migration guide — llmemory

This guide covers the critical bug-fix release (P0) introduced **after 0.2.4**. If you are upgrading from 0.2.4 or earlier, follow the steps that apply to your setup.

## Summary of changes

| Area | Before | After | Action in your app |
|------|--------|-------|------------------|
| Keyword search + encryption (Postgres/AR) | `LIKE` on ciphertext → 0 results | Blind index on `search_tokens` column | DB migration + backfill recommended |
| `find_skills_by_name` + encryption (Postgres) | `data->>'name'` on encrypted blob → always empty | `name_det` column with deterministic encryption | DB migration + skill backfill |
| In-memory vector store (episodic/procedural) | IDs `"user_id:id"` → lookup fails | Clean IDs (`"id"`) | None |
| Graph + `long_term_store: :file`/`:postgres` | Silently fell back to volatile memory | Explicit `ConfigurationError` | Fix configuration |
| MCP timeline + `:file` store | Silent `NotImplementedError` | `get_items_around` implemented | None |
| MCP timeline + graph | File-based only | Graph edges supported | None |

## Quick checklist

```
□ bundle update llmemory
□ Review long_term_type / long_term_store (graph does not support :file or :postgres)
□ If encryption_enabled: migrate search_tokens columns (+ name_det on skills)
□ If you have existing encrypted data: run backfill
□ Restart workers / Puma / jobs
□ Verify search, vector retrieval, and MCP timeline
```

---

## 1. Update the gem

```bash
bundle update llmemory
```

Restart any processes that load the gem (Puma, Sidekiq, MCP workers, etc.).

---

## 2. Graph-based memory configuration (breaking change)

If you have:

```ruby
Llmemory.configure do |c|
  c.long_term_type = :graph_based
  c.long_term_store = :file   # or :postgres
end
```

The gem **no longer** silently falls back to in-memory storage. Startup will raise:

```text
Llmemory::ConfigurationError: graph_based long-term memory supports long_term_store :memory or :active_record; got ":file"
```

**Fix:** use a supported backend:

```ruby
c.long_term_store = :memory          # development / tests
c.long_term_store = :active_record   # production with Rails + PostgreSQL (+ pgvector)
```

Graph-based memory does **not** have `:file` or `:postgres` backends yet.

---

## 3. Database migration

### New installations (Rails)

`rails g llmemory:install` already generates `search_tokens` and `name_det` in the install migration template. Run:

```bash
rails db:migrate
```

### Existing installations (Rails + ActiveRecord)

Create a migration:

```ruby
# db/migrate/XXXXXX_add_search_tokens_to_llmemory.rb
class AddSearchTokensToLlmemory < ActiveRecord::Migration[7.0]
  def change
    add_column :llmemory_items, :search_tokens, :text
    add_column :llmemory_resources, :search_tokens, :text
    add_column :llmemory_episodes, :search_tokens, :text
    add_column :llmemory_skills, :search_tokens, :text
    add_column :llmemory_skills, :name_det, :text
  end
end
```

```bash
rails db:migrate
```

> **Note:** ActiveRecord storages detect the column via `column_names.include?("search_tokens")`. Without the migration, encrypted keyword search **does not improve** (still uses `LIKE` on ciphertext).

### Direct Postgres (`long_term_store: :postgres`, no Rails)

No manual migration is required: `ensure_tables!` runs:

```sql
ALTER TABLE llmemory_items ADD COLUMN IF NOT EXISTS search_tokens TEXT;
ALTER TABLE llmemory_resources ADD COLUMN IF NOT EXISTS search_tokens TEXT;
ALTER TABLE llmemory_episodes ADD COLUMN IF NOT EXISTS search_tokens TEXT;
ALTER TABLE llmemory_skills ADD COLUMN IF NOT EXISTS search_tokens TEXT;
ALTER TABLE llmemory_skills ADD COLUMN IF NOT EXISTS name_det TEXT;
```

on first access to the storage layer.

### `:memory` and `:file` backends

No schema migration required. Keyword search decrypts in Ruby as before.

---

## 4. Encryption enabled — backfill existing data

With `encryption_enabled: true`, **new writes** automatically populate:

- `search_tokens` — HMAC blind index per search token
- `name_det` — deterministically encrypted skill name (procedural only)

Rows written **before** the migration have `search_tokens IS NULL`. The gem includes a **fallback**: it loads and decrypts those rows in Ruby (`Tokenizer.matches?`). This works, but:

- It is slower on large tables
- Legacy rows are decrypted on every search until backfilled

**Recommendation:** run backfill after deploying the migration.

### Option A — Rake task (recommended)

```bash
# Pending rows (search_tokens IS NULL; skills also name_det IS NULL)
bundle exec rake llmemory:backfill_search_tokens

# Single user
bundle exec rake llmemory:backfill_search_tokens[user_123]

# Dry run (no writes)
DRY_RUN=1 bundle exec rake llmemory:backfill_search_tokens

# Re-backfill even when index already set
FORCE=1 bundle exec rake llmemory:backfill_search_tokens

# Explicit backend (default: Llmemory.configuration.long_term_store)
STORE=active_record bundle exec rake llmemory:backfill_search_tokens
STORE=postgres bundle exec rake llmemory:backfill_search_tokens
```

Requirements: `long_term_store` `:active_record` or `:postgres`, migrated columns, `DATABASE_URL` / ActiveRecord configured, same `encryption_key` used when the data was written.

Implementation: `Llmemory::Maintenance::SearchTokensBackfill` (`lib/llmemory/maintenance/search_tokens_backfill.rb`).

### Option B — Manual in-place script

In a Rails console or Ruby script with access to the cipher:

```ruby
# Pseudocode — run per model/table
include Llmemory::Crypto::FieldHelpers

def backfill_item(item_record)
  plain = dec(item_record.content)
  item_record.update_column(:search_tokens, search_tokens_for(plain))
end
```

Repeat for `llmemory_resources`, `llmemory_episodes`, `llmemory_skills` (decrypted `search_text`), and `name_det` on skills (`enc_det(skill_name)`).

Or call the maintenance API directly:

```ruby
Llmemory::Maintenance::SearchTokensBackfill.new(dry_run: false).run(user_id: "user_123")
```

### Encrypted search semantics

With the blind index enabled, matching is **exact-token** (`ruby`, `python`), not partial substring within a token. This matches `Llmemory::Tokenizer` (`[a-z0-9]{2,}`).

---

## 5. Encryption disabled

If `encryption_enabled: false`:

| Backend | Action |
|---------|--------|
| `:memory`, `:file` | None |
| `:postgres` | Optional; columns are auto-created |
| `:active_record` | Migration recommended to align schema with new installs |

Search continues to use `LIKE` on plaintext; `search_tokens` may remain `NULL`.

---

## 6. Vector retrieval (episodic / procedural)

If you use:

```ruby
config.episodic_vector_enabled = true
# or
config.procedural_vector_enabled = true
```

with `long_term_store` other than `:active_record` (in-memory vector store):

- **No configuration changes required**
- Vector search now returns clean IDs (`ep_abc`, not `user:ep_abc`)
- Semantic retrieval should work without code changes

---

## 7. MCP and timeline

| Scenario | Effect |
|----------|--------|
| `long_term_store: :file` + timeline tools | Works (`get_items_around` / `get_resources_around`) |
| `long_term_type: :graph_based` + `MemoryTimeline` | Lists recent graph relations |
| `MemoryTimelineContext` + graph | Uses `get_edges_around` |
| `MemoryRetrieve` + timeline + graph | Skips timeline context (item anchoring does not apply) |

Usually no changes needed in MCP clients.

---

## 8. Post-migration verification

### Encrypted search

```ruby
Llmemory.configure { |c| c.encryption_enabled = true; c.encryption_key = ENV["LLMEMORY_ENCRYPTION_KEY"] }
memory = Llmemory::Memory.new(user_id: "test_user")
memory.consolidate! # or write facts manually
results = memory.long_term.search_items("ruby") # adjust to your API
expect(results).not_to be_empty
```

### Graph with invalid store

```ruby
expect {
  Llmemory::LongTerm::GraphBased::Storages.build(store: :file)
}.to raise_error(Llmemory::ConfigurationError)
```

### Vector + episodic

```ruby
# With episodic_vector_enabled and store :memory
episodic = memory.episodic
episodic.write(steps: [{ action: "deploy app" }])
candidates = episodic.search_candidates("deploy")
expect(candidates).not_to be_empty
expect(candidates.first[:id]).not_to include(":")
```

---

## 9. What does not change

- Public API (`Memory.new`, `retrieve`, `consolidate!`, `maintain!`, etc.)
- File format on the `:file` backend
- Encryption keys (`LLMEMORY_ENCRYPTION_KEY`, per-instance `encryption_key`)
- Existing encrypted data remains readable with the same key
- Short-term checkpoints, graph nodes/edges, embeddings (no mandatory schema change)

---

## Support

If something does not match your stack, open an issue with:

- `long_term_type`, `long_term_store`, `short_term_store`
- `encryption_enabled`
- Episodic/procedural backends if used
- llmemory and Ruby versions
