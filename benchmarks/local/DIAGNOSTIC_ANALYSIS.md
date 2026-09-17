# Diagnostic analysis (hybrid suite)

Generated as part of hybrid + `suite-diag` implementation. Re-run after `./benchmarks/local/run_benchmarks.sh suite-diag` with LM Studio and `qwen3-4b-instruct-2507`.

## How to read results

1. Primary: **`retrieval_hit`** and **`localization.recall@5`** per row (retrieve layer).
2. Secondary: **`bench_scores`** (F1 / EM / judges) — answer layer; do not tune the reader to lift these alone.
3. Compare **`classic`** vs **`zero_mem_full`** vs **`hybrid`** on the same bench/limit.

Aggregate file: `benchmarks/local/results/suite_diag_<timestamp>.json`.

## Stub-LLM LoCoMo probe (`diag_locomo.rb`)

One conversation, temporal QA (“When did Caroline go to the LGBTQ support group?”), gold turn `D1:3`.

| Variant | Gold partial in context? | Gold in ranked top 5? | Notes |
|---------|--------------------------|------------------------|-------|
| classic | no | no | 0 extracted items; 19 resources; retrieve biased to recent sessions (ranked ids from D18…) |
| zero_mem_full | yes | no | Evidence includes LGBTQ wording; ranking still misses gold turn id in top 5 |
| hybrid | yes | no | Fused context includes `ZERO-MEM EVIDENCE` + classic block; same ranking gap as zero_mem |

**Layers implicated (LoCoMo sample):**

- **Extract:** classic stub returns `[]` for facts → `stored items: 0`; temporal answer depends on resources/raw dialogue in retrieve, not consolidated facts.
- **Retrieve (classic):** recency / session skew — gold from session 1 not in top-ranked context.
- **Retrieve (zero_mem / hybrid):** lexical hit on gold text but **localization** still fails (gold trace id not in top 5).
- **Temporal / answer:** not measured with stub reader; run with `--reader llm` under LM Studio.

## Product priorities (evidence-based so far)

1. **Classic retrieval ranking** for short temporal queries over long multi-session history (`Retrieval::Engine` / temporal ranker / candidate pool).
2. **Zero-Mem localization** — align ranked trace ids with dataset turn ids (calibration / fusion weights on long dialogs).
3. **Hybrid token budget** — tune `hybrid_classic_token_ratio` if classic block crowds out evidence (watch `recall@5` vs zero_mem-only).
4. **Consolidation yield** — ensure real LLM extraction populates items with absolute dates (timestamp WIP + extractor content); stub hides this in diag.

## Dataset readiness (env paths in `benchmarks.env`)

| Bench | Status |
|-------|--------|
| locomo | ready |
| longmemeval | clone present; download `longmemeval_oracle.json` into `LongMemEval/data/` (not in shallow clone) |
| groupmembench | ready |
| memoryagentbench, locomo_plus, memsyco, mem2act, memory_arena | manual export required (see `benchmarks/local/data/README.md`) |

## Next command (when LM Studio is up)

```bash
./benchmarks/local/run_benchmarks.sh check
./benchmarks/local/run_benchmarks.sh suite-diag
bundle exec ruby benchmarks/local/diag_locomo.rb
```

Interpret `suite_diag_*.json` and update this file with numeric means per bench/variant.
