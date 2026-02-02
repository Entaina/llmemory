# llmemory

Persistent memory system for LLM agents. Implements short-term checkpointing, long-term memory (file-based or **graph-based**), retrieval with time decay, and maintenance jobs. You can inspect memory from the **CLI** or, in Rails apps, from an optional **dashboard**.

## Installation

Add to your Gemfile:

```ruby
gem "llmemory"
```

Then run `bundle install`.

## Quick Start (Unified API)

The recommended way to use llmemory in a chat is the unified `Llmemory::Memory` API. It abstracts short-term (conversation history) and long-term (extracted facts) and combines retrieval from both:

```ruby
# File-based long-term (default): facts and categories
memory = Llmemory::Memory.new(user_id: "user_123", session_id: "conv_456")

# Or graph-based long-term: entities and relations (knowledge graph + vector search)
memory = Llmemory::Memory.new(user_id: "user_123", session_id: "conv_456", long_term_type: :graph_based)

# Add user and assistant messages
memory.add_message(role: :user, content: "Soy vegano y trabajo en OpenAI")
memory.add_message(role: :assistant, content: "Entendido, lo recordaré")

# Get full context for the next LLM call (recent conversation + relevant long-term memories)
context = memory.retrieve("¿Qué preferencias tiene el usuario?", max_tokens: 2000)

# Optionally consolidate current conversation into long-term (extract facts)
memory.consolidate!

# Clear session (short-term) while keeping long-term intact
memory.clear_session!
```

- **`add_message(role:, content:)`** — Persists messages in short-term.
- **`messages`** — Returns the current conversation history.
- **`retrieve(query, max_tokens: nil)`** — Returns combined context: recent conversation + relevant long-term memories.
- **`consolidate!`** — Extracts facts from the current conversation and stores them in long-term.
- **`clear_session!`** — Clears short-term only.

## Configuration

```ruby
Llmemory.configure do |config|
  config.llm_provider = :openai
  config.llm_api_key = ENV["OPENAI_API_KEY"]
  config.llm_model = "gpt-4"
  config.short_term_store = :memory  # or :redis, :postgres, :active_record
  config.redis_url = ENV["REDIS_URL"]  # for :redis
  config.long_term_type = :file_based  # or :graph_based (entities + relations)
  config.long_term_store = :memory  # or :file, :postgres, :active_record
  config.long_term_storage_path = "./llmemory_data"  # for :file
  config.database_url = ENV["DATABASE_URL"]          # for :postgres
  config.time_decay_half_life_days = 30
  config.max_retrieval_tokens = 2000
  config.prune_after_days = 90
end
```

## Long-Term Storage

Long-term memory can use different backends:

| Store            | Class                       | Use case                          |
|------------------|-----------------------------|-----------------------------------|
| `:memory`        | `Storages::MemoryStorage`   | Default; in-memory, lost on exit  |
| `:file`          | `Storages::FileStorage`     | Persist to disk (directory per user) |
| `:postgres`      | `Storages::DatabaseStorage` | PostgreSQL (tables created automatically) |
| `:active_record` | `Storages::ActiveRecordStorage` | Rails: usa ActiveRecord y tu DB existente |

Set `config.long_term_store = :file`, `:postgres` or `:active_record` so that `Llmemory::Memory` and `FileBased::Memory` use it when no `storage:` is passed.

**Long-term type:** use `long_term_type: :graph_based` in `Llmemory::Memory.new(...)` for entity/relation memory (knowledge graph + hybrid retrieval). See [Long-Term Memory (Graph-Based)](#long-term-memory-graph-based) below.

**Rails (ActiveRecord):** añade `activerecord` a tu Gemfile si no está. Luego:

```bash
rails g llmemory:install
rails db:migrate
```

La migración crea las tablas de long-term file-based (resources, items, categories), short-term (checkpoints) y, para graph-based, nodos, aristas y embeddings (`llmemory_nodes`, `llmemory_edges`, `llmemory_embeddings`). Para embeddings se usa pgvector; asegúrate de tener la extensión `vector` en PostgreSQL. Para usar ambas con ActiveRecord:

```ruby
# config/application.rb o config/initializers/llmemory.rb
Llmemory.configure do |config|
  config.short_term_store = :active_record   # historial de conversación en DB
  config.long_term_store = :active_record    # hechos extraídos en DB
  # ... llm, etc.
end
```

Explicit storage:

```ruby
storage = Llmemory::LongTerm::FileBased::Storages.build(store: :file, base_path: "./data/llmemory")
memory = Llmemory::LongTerm::FileBased::Memory.new(user_id: "u1", storage: storage)

storage = Llmemory::LongTerm::FileBased::Storages.build(store: :postgres, database_url: ENV["DATABASE_URL"])
memory = Llmemory::LongTerm::FileBased::Memory.new(user_id: "u1", storage: storage)

# Rails
storage = Llmemory::LongTerm::FileBased::Storages.build(store: :active_record)
memory = Llmemory::LongTerm::FileBased::Memory.new(user_id: "u1", storage: storage)
```

## Long-Term Memory (Graph-Based)

When you need **entities and relations** (e.g. “User works_at OpenAI”, “User prefers Ruby”) instead of flat facts and categories, use graph-based long-term memory. It combines:

- **Knowledge graph** — Nodes (entities) and edges (subject–predicate–object relations).
- **Vector store** — Embeddings (e.g. OpenAI `text-embedding-3-small`) for semantic search.
- **Hybrid retrieval** — Vector search + graph traversal from matched nodes, then merged and ranked.
- **Conflict resolution** — Exclusive predicates (e.g. `works_at`, `lives_in`) archive previous values when a new one is stored.

### Unified API with graph-based

```ruby
memory = Llmemory::Memory.new(
  user_id: "user_123",
  session_id: "conv_456",
  long_term_type: :graph_based
)
memory.add_message(role: :user, content: "Trabajo en Acme y vivo en Madrid")
memory.consolidate!
context = memory.retrieve("¿Dónde trabaja el usuario?")
```

### Lower-level graph-based API

```ruby
storage = Llmemory::LongTerm::GraphBased::Storages.build(store: :memory)  # or :active_record
vector_store = Llmemory::VectorStore::MemoryStore.new(
  embedding_provider: Llmemory::VectorStore::OpenAIEmbeddings.new
)
memory = Llmemory::LongTerm::GraphBased::Memory.new(
  user_id: "user_123",
  storage: storage,
  vector_store: vector_store
)
memory.memorize("User works at Acme. User lives in Madrid.")
context = memory.retrieve("where does user work", top_k: 10)
candidates = memory.search_candidates("job", top_k: 20)
```

- **`memorize(conversation_text)`** — LLM extracts entities and relations (SPO triplets), upserts nodes/edges, resolves conflicts, and stores relation text in the vector store.
- **`retrieve(query, top_k:)`** — Hybrid search: vector similarity + graph traversal; returns formatted context string.
- **`search_candidates(query, user_id:, top_k:)`** — Used by `Retrieval::Engine`; returns `[{ text:, timestamp:, score: }]`.

**Graph storage:** `:memory` (in-memory) or `:active_record` (Rails). For ActiveRecord, run `rails g llmemory:install` and migrate; the migration creates `llmemory_nodes`, `llmemory_edges`, and `llmemory_embeddings` (pgvector). Enable the `vector` extension in PostgreSQL for embeddings.

## Lower-Level APIs

### Short-Term Memory (Checkpointing)

```ruby
checkpoint = Llmemory::ShortTerm::Checkpoint.new(user_id: "user_123")
checkpoint.save_state(conversation_state)
state = checkpoint.restore_state
```

### Long-Term Memory (File-Based)

```ruby
memory = Llmemory::LongTerm::FileBased::Memory.new(user_id: "user_123")
# or with explicit storage: storage: Llmemory::LongTerm::FileBased::Storages.build(store: :file)
memory.memorize(conversation_text)
context = memory.retrieve(query)
```

### Retrieval Engine

```ruby
retrieval = Llmemory::Retrieval::Engine.new(long_term_memory)
context = retrieval.retrieve_for_inference(user_message, max_tokens: 2000)
```

### Maintenance

```ruby
Llmemory::Maintenance::Runner.run_nightly(user_id, storage: memory.storage)
Llmemory::Maintenance::Runner.run_weekly(user_id, storage: memory.storage)
Llmemory::Maintenance::Runner.run_monthly(user_id, storage: memory.storage)
```

## Inspecting memory

### CLI

The gem ships an executable to inspect memory from the terminal (no extra dependencies; uses Ruby’s OptParse):

```bash
llmemory --help
llmemory users
llmemory short-term USER_ID [--session SESSION_ID] [--list-sessions]
llmemory facts USER_ID [--category CATEGORY] [--limit N]
llmemory categories USER_ID
llmemory resources USER_ID [--limit N]
llmemory nodes USER_ID [--type TYPE] [--limit N]      # graph-based
llmemory edges USER_ID [--subject NODE_ID] [--limit N]
llmemory graph USER_ID [--format dot|json]
llmemory search USER_ID "query" [--type short|long|all]
llmemory stats [USER_ID]
```

Use `--store TYPE` where applicable to override the configured store (e.g. `memory`, `redis`, `postgres`, `active_record` for short-term; same or `file` for long-term file-based).

### Dashboard (Rails, optional)

If you use Rails and want a web UI to browse memory, load the dashboard and mount the engine. **Rails is not a dependency of the gem**; the dashboard is only loaded when you require it.

1. In an initializer or early in boot (e.g. `config/initializers/llmemory.rb`):

```ruby
require "llmemory/dashboard"
```

2. In `config/routes.rb`:

```ruby
mount Llmemory::Dashboard::Engine, at: "/llmemory"
```

3. Visit `/llmemory`. You get:
   - List of users with memory
   - Short-term: conversation messages per session
   - Long-term (file-based): resources, items by category, category summaries
   - Long-term (graph-based): nodes and edges
   - Search and stats

The dashboard uses your existing `Llmemory.configuration` (short-term store, long-term store/type, etc.) and does not add any gem dependency; it only runs when Rails is present and you require `llmemory/dashboard`.

## License

MIT. See [LICENSE.txt](LICENSE.txt).
