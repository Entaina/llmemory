---
name: llmemory-benchmarks-dev
description: Extends or fixes llmemory memory benchmarks (benchmarks/local, benchmarks/zero_mem) and ties bench work to product improvements in lib/llmemory. Use when adding adapters, harness metrics, LoCoMo/LM Studio runs, or fixing failures exposed by benches—never to inflate scores without fixing Memory/consolidate/retrieve.
---

# llmemory — Benchmark development (product-first)

## Principle (non-negotiable)

**La idea es mejorar llmemory, no mejorar en los benchmarks.**

- If benchmarks become **more useful** for identifying llmemory weaknesses → good.
- If we **only** improve benchmark code (prompts, adapters, scoring) so numbers go up **without** fixing consolidation, retrieval, or temporal memory in `lib/llmemory` → **do not ship that**; it hides regressions.

Success criterion for a change:

- Same bench command, same local model, same **strict** eval reader.
- Scores improve because **`Memory#retrieve` / `retrieve_evidence` / `consolidate!`** behave better (e.g. gold evidence appears in context, dated facts).
- Improving **only** `ReaderLLM` or injecting oracle context **does not** count as fixing llmemory.

## Allowed benchmark work

| OK | Why |
|----|-----|
| Faithful dataset adapters (canonical protocol, real API fields) | Measures product honestly |
| Pass **`occurred_at`** / metadata via `add_message` / `record_trace` when datasets provide it | Uses existing Memory API |
| Layered metrics: extraction yield, **retrieval_hit** (gold span in context), answer F1 | Locates failure layer |
| `diag_locomo.rb`, README, `run_benchmarks.sh` | Operability |
| Per-session consolidate in harness to respect LM context limits | Infrastructure; not score cheating |

## Forbidden (benchmark-only cheating)

| Avoid | Why |
|-------|-----|
| Looser reader prompt (“infer dates freely”) to lift F1 | Eval change, not memory |
| Oracle retrieval (gold turn ids fed to reader) | Not deployable |
| Inject gold answers or session dates into context in the adapter | Masks retrieve failures |
| Benchmark-specific hacks inside `lib/llmemory` gated by `ENV["BENCH"]` | Pollutes product |

Product fixes belong in **`lib/llmemory`** with **general** behavior and specs under `spec/`, not bench-only branches.

## Known product gaps LoCoMo exposes (fix here first)

1. **`consolidate!`** — `format_message` drops message `occurred_at`; facts/resources get consolidation-time timestamps → temporal QA fails.
2. **Retrieve** — short queries + many lexical items → relevant facts not in assembled context (ranking/BM25/hybrid).
3. **Zero_mem** — long dialogs: recency bias; needs correct trace times and ranking.
4. **Fact extraction** — paraphrases without absolute dates; should combine relative language + message/session time in stored content or provenance.

Prioritize PRs that move **retrieval_hit** and real retrieve context before tuning the bench reader.

## Code map

| Area | Path |
|------|------|
| Local bench runner | `benchmarks/local/runners/run.rb`, `run_benchmarks.sh` |
| Harness | `benchmarks/local/harness.rb`, `benchmarks/zero_mem/harness.rb` |
| Adapters | `benchmarks/local/adapters/` |
| Scorers | `benchmarks/local/scorers/` |
| Product entry | `lib/llmemory/memory.rb` (`consolidate!`, `retrieve`, `add_message`) |
| File-based LT | `lib/llmemory/long_term/file_based/` |
| Retrieval | `lib/llmemory/retrieval/engine.rb`, `context_assembler.rb` |

## Tests

- Bench specs: `spec/benchmarks/local/` — WebMock LM Studio; datasets optional (`skip` without `*_DATASET_ROOT`).
- Product changes: `bundle exec rspec` for touched lib specs; do not require LM Studio in CI.

## When implementing a bench-driven fix

1. Reproduce with `diag_locomo.rb` or one `--limit 20` run; note which layer fails (extract / retrieve / answer).
2. Implement fix in **llmemory** with a focused spec.
3. Re-run same bench command; confirm **localization / retrieval_hit** improves, not only F1 via reader.
