# llmemory

Persistent memory system for LLM agents. Implements short-term checkpointing, long-term file-based and graph-based memory, retrieval with time decay, and maintenance jobs.

## Installation

Add to your Gemfile:

```ruby
gem "llmemory"
```

Then run `bundle install`.

## Configuration

```ruby
Llmemory.configure do |config|
  config.llm_provider = :openai
  config.llm_api_key = ENV["OPENAI_API_KEY"]
  config.llm_model = "gpt-4"
  config.short_term_store = :redis
  config.redis_url = ENV["REDIS_URL"]
  config.long_term_store = :postgres
  config.database_url = ENV["DATABASE_URL"]
  config.vector_store = :pgvector
  config.time_decay_half_life_days = 30
  config.max_retrieval_tokens = 2000
  config.prune_after_days = 90
end
```

## Short-Term Memory (Checkpointing)

```ruby
checkpoint = Llmemory::ShortTerm::Checkpoint.new(user_id: "user_123")
checkpoint.save_state(conversation_state)
state = checkpoint.restore_state
```

## Long-Term Memory (File-Based)

```ruby
memory = Llmemory::LongTerm::FileBased::Memory.new(user_id: "user_123")
memory.memorize(conversation_text)
context = memory.retrieve(query)
```

## Retrieval

```ruby
retrieval = Llmemory::Retrieval::Engine.new(memory)
context = retrieval.retrieve_for_inference(user_message, max_tokens: 2000)
```

## Maintenance

```ruby
Llmemory::Maintenance::Runner.run_nightly(user_id)
Llmemory::Maintenance::Runner.run_weekly(user_id)
Llmemory::Maintenance::Runner.run_monthly(user_id)
```

## License

MIT. See [LICENSE.txt](LICENSE.txt).
