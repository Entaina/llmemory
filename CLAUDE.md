# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

llmemory is a Ruby gem providing persistent memory for LLM agents. It implements short-term checkpointing (conversation history), long-term memory (file-based facts or graph-based entities/relations), retrieval with time decay, and maintenance jobs.

## Build & Test Commands

```bash
bundle install              # Install dependencies
bundle exec rspec           # Run all tests
bundle exec rspec spec/path/to/spec.rb  # Run single test file
rake spec                   # Run tests via Rakefile (default task)
```

## Architecture

### Core Components

- **`Llmemory::Memory`** (`lib/llmemory/memory.rb`) - Unified API combining short-term and long-term memory. Primary entry point for most use cases.

- **Short-term** (`lib/llmemory/short_term/`) - Conversation history via `Checkpoint`. Storage backends: memory, Redis, PostgreSQL, ActiveRecord.

- **Long-term File-based** (`lib/llmemory/long_term/file_based/`) - Facts, categories, and resources extracted from conversations. Uses `FactExtractor` to process text via LLM.

- **Long-term Graph-based** (`lib/llmemory/long_term/graph_based/`) - Knowledge graph with nodes (entities) and edges (subject-predicate-object relations). Uses `EntityRelationExtractor` and vector embeddings for hybrid retrieval.

- **Long-term Episodic** (`lib/llmemory/long_term/episodic/`) - Experience trajectories (`Episode` = ordered observation→action→result steps). CoALA episodic memory; `:memory`/`:file` backends, keyword retrieval.

- **Long-term Procedural** (`lib/llmemory/long_term/procedural/`) - Voyager-style `Skill` library (prompt/template/code) with auto-versioning and success/failure tracking; success rate surfaced as retrieval importance.

- **Working memory** (`lib/llmemory/working_memory.rb`) - `WorkingMemory`: structured symbolic slots persisted across LLM calls via the short-term stores (namespaced session key). Exposed as `Memory#working_memory`.

- **MemoryModule** (`lib/llmemory/memory_module.rb`) - Uniform contract (`read`/`write`/`list`/`stats`/`forget`) mixed into the four queryable long-term memories.

- **Reflection** (`lib/llmemory/reflection/`) - `Reflector` distills recent episodes into semantic insights (Reflexion / Generative Agents pattern) with provenance to source episodes.

- **Actions** (`lib/llmemory/actions/`) - `Reason`: render prompt from working memory → LLM → write result back (CoALA reasoning action).

- **Provenance / ForgetLog** (`lib/llmemory/provenance.rb`, `lib/llmemory/forget_log.rb`) - Lineage on items/nodes/edges/insights (sources, method, confidence); `ForgetLog` audits removals.

- **LLM Providers** (`lib/llmemory/llm/`) - OpenAI and Anthropic implementations with structured output support.

- **Retrieval** (`lib/llmemory/retrieval/`) - `Engine` orchestrates retrieval, `TemporalRanker` applies time decay + importance, `ContextAssembler` formats output. `FeedbackStore` + `Engine#report_feedback` enable adaptive retrieval; `Engine#iterative_retrieve` does multi-hop retrieval.

- **MCP Server** (`lib/llmemory/mcp/`) - Model Context Protocol server for agent integration. HTTP and stdio transports. Optional dependency on `mcp` gem.

- **CLI** (`lib/llmemory/cli.rb`, `exe/llmemory`) - Command-line interface for inspecting memory.

### Storage Pattern

All storage backends use a factory pattern:
```ruby
Llmemory::LongTerm::FileBased::Storages.build(store: :file, base_path: "./data")
Llmemory::LongTerm::GraphBased::Storages.build(store: :active_record)
```

### Data Flow

1. Messages → `Checkpoint` (short-term storage)
2. `consolidate!` → Extractor (LLM) → Long-term storage (facts or graph)
3. `retrieve(query)` → TemporalRanker + ContextAssembler → Formatted context

## Key Configuration

Configure via `Llmemory.configure` block. Key options:
- `llm_provider`: `:openai` or `:anthropic`
- `short_term_store`: `:memory`, `:redis`, `:postgres`, `:active_record`
- `long_term_type`: `:file_based` or `:graph_based`
- `long_term_store`: `:memory`, `:file`, `:postgres`, `:active_record`

## Graph-based Memory

Requires pgvector extension for PostgreSQL. Uses vector embeddings for semantic search combined with graph traversal. `ConflictResolver` handles exclusive predicates (e.g., only one `works_at` value).

## Rails Integration

Dashboard engine in `lib/llmemory/dashboard/`. Must be required in `config/application.rb` (not initializer). Migrations created via `rails g llmemory:install`.
