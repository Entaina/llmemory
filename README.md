# llmemory

Persistent memory system for LLM agents. Implements short-term checkpointing, long-term file-based memory, retrieval with time decay, and maintenance jobs.

## Installation

Add to your Gemfile:

```ruby
gem "llmemory"
```

Then run `bundle install`.

## Quick Start (Unified API)

The recommended way to use llmemory in a chat is the unified `Llmemory::Memory` API. It abstracts short-term (conversation history) and long-term (extracted facts) and combines retrieval from both:

```ruby
memory = Llmemory::Memory.new(user_id: "user_123", session_id: "conv_456")

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

**Rails (ActiveRecord):** añade `activerecord` a tu Gemfile si no está. Luego:

```bash
rails g llmemory:install
rails db:migrate
```

La migración crea las tablas de long-term (resources, items, categories) y la de short-term (checkpoints). Para usar ambas con ActiveRecord:

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

## License

MIT. See [LICENSE.txt](LICENSE.txt).
