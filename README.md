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

The dashboard must be **required early in boot** (in `config/application.rb`), not in an initializer, so that Rails registers the engine’s routes correctly (same as other engines like mailbin).

**1. Require the dashboard in `config/application.rb`** (e.g. right after `Bundler.require`):

```ruby
# config/application.rb
Bundler.require(*Rails.groups)

require "llmemory/dashboard" if Rails.env.development?  # optional: only in development
```

**2. Configure llmemory** in `config/initializers/llmemory.rb` (store, LLM, etc.):

```ruby
# config/initializers/llmemory.rb
Llmemory.configure do |config|
  config.llm_provider = :openai
  config.llm_api_key = ENV["OPENAI_API_KEY"]
  config.short_term_store = :active_record
  config.long_term_type = :graph_based
  config.long_term_store = :active_record
  # ...
end
```

**3. Mount the engine** in `config/routes.rb` (you can wrap it in a development check or behind auth):

```ruby
# config/routes.rb
Rails.application.routes.draw do
  # ...
  mount Llmemory::Dashboard::Engine, at: "/llmemory" if Rails.env.development?
end
```

**4. Visit** `/llmemory`. You get:

- List of users with memory
- Short-term: conversation messages per session
- Long-term (file-based): resources, items by category, category summaries
- Long-term (graph-based): nodes and edges
- Search and stats

The dashboard uses your existing `Llmemory.configuration` (short-term store, long-term store/type, etc.) and does not add any gem dependency; it only runs when Rails is present and you require `llmemory/dashboard`.

## MCP Server (Model Context Protocol)

llmemory includes an MCP server that allows LLM agents (like Claude Code) to interact directly with the memory system. This gives agents "agency" over their own memory—they can search, save, and retrieve memories autonomously.

### Starting the Server

**Stdio mode** (default, for local use with Claude Code):

```bash
# Via CLI
llmemory mcp serve

# Or via standalone executable
llmemory-mcp

# With custom server name
llmemory mcp serve --name my-memory
```

**HTTP mode** (for remote access or web integrations):

```bash
# Start HTTP server on default port 3100
llmemory mcp serve --http

# Custom port and host
llmemory mcp serve --http --port 8080 --host 127.0.0.1

# With authentication (recommended for HTTP/HTTPS)
MCP_TOKEN=your-secret-token llmemory mcp serve --http
```

**HTTPS mode** (secure remote access):

```bash
# Start HTTPS server with SSL certificates
llmemory mcp serve --http --port 443 \
  --ssl-cert /path/to/cert.pem \
  --ssl-key /path/to/key.pem

# With authentication (strongly recommended)
MCP_TOKEN=your-secret-token llmemory mcp serve --http --port 443 \
  --ssl-cert /path/to/cert.pem \
  --ssl-key /path/to/key.pem
```

### Available Tools

| Tool | Description |
|------|-------------|
| `memory_search` | Search memories by semantic query |
| `memory_save` | Save new observations/facts to long-term memory |
| `memory_retrieve` | Get context optimized for LLM inference (supports timeline context) |
| `memory_timeline` | Get chronological timeline of recent memories |
| `memory_timeline_context` | Get N items before/after a specific memory |
| `memory_add_message` | Add message to short-term conversation |
| `memory_consolidate` | Extract facts from conversation to long-term |
| `memory_stats` | Get memory statistics for a user |
| `memory_info` | Documentation on how to use the tools |

### Configuration for Claude Code

Add to `~/.claude/claude_code_config.json`:

```json
{
  "mcpServers": {
    "llmemory": {
      "command": "llmemory",
      "args": ["mcp", "serve"],
      "env": {
        "OPENAI_API_KEY": "sk-..."
      }
    }
  }
}
```

Or with the standalone executable:

```json
{
  "mcpServers": {
    "llmemory": {
      "command": "llmemory-mcp"
    }
  }
}
```

### Environment Variables

| Variable | Description |
|----------|-------------|
| `MCP_TOKEN` | Token for HTTP authentication (if set, requests must include valid token) |
| `LLMEMORY_DEBUG` | Set to `1` to enable debug output on stderr |
| `OPENAI_API_KEY` | API key for LLM/embeddings |
| `REDIS_URL` | Redis URL for short-term store |
| `DATABASE_URL` | Database URL for persistence |

### HTTP Authentication

When `MCP_TOKEN` is set, the HTTP server requires authentication. Requests must include the token via:

- **Authorization header**: `Authorization: Bearer <token>` or `Authorization: <token>`
- **Query parameter**: `?token=<token>`

Example with curl:

```bash
# Using Authorization header
curl -H "Authorization: Bearer your-secret-token" \
  -H "Accept: application/json, text/event-stream" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' \
  http://localhost:3100/

# Using query parameter
curl "http://localhost:3100/?token=your-secret-token" \
  -H "Accept: application/json, text/event-stream" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}'
```

### Recommended Workflow

1. **Start of conversation**: Use `memory_retrieve` to get relevant context
2. **During conversation**: Use `memory_save` for important observations
3. **End of conversation**: Use `memory_consolidate` to persist facts

### Timeline Context

The `memory_retrieve` tool supports **timeline context** - showing N events before and after matched memories. This provides situational context around relevant memories:

```json
{
  "name": "memory_retrieve",
  "arguments": {
    "query": "trabajo",
    "user_id": "user123",
    "include_timeline_context": true,
    "timeline_window": 3
  }
}
```

This returns:
- Recent conversation (short-term)
- Relevant memories (long-term)
- **Timeline context**: 3 events before and after each match

You can also use `memory_timeline_context` directly to explore temporal context around a specific memory:

```json
{
  "name": "memory_timeline_context",
  "arguments": {
    "user_id": "user123",
    "item_id": "item_42",
    "before": 5,
    "after": 5
  }
}
```

Example output:
```
Timeline Context around 'item_42':

BEFORE (3 items):
  - [2024-01-14] [personal] Usuario vive en Madrid
  - [2024-01-15] [technical] Usuario programa en Python
  - [2024-01-16] [preferences] Usuario usa VS Code

TARGET:
>>> [2024-01-17] [work] Usuario trabaja en Acme Corp

AFTER (3 items):
  - [2024-01-18] [personal] Usuario tiene un gato
  - [2024-01-19] [work] Usuario lidera equipo backend
  - [2024-01-20] [preferences] Usuario prefiere café
```

## License

MIT. See [LICENSE.txt](LICENSE.txt).
