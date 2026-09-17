---
name: llmemory-benchmarks
description: Runs and interprets llmemory local memory benchmarks (LM Studio, LoCoMo, LongMemEval, benchmarks/local). Use when executing run_benchmarks.sh, configuring benchmarks.env, comparing classic vs zero_mem, or reading bench JSON results—not when changing harness code (use llmemory-benchmarks-dev).
---

# llmemory — Local memory benchmarks

## North star

**Improve llmemory, not benchmark scores.** Benchmarks exist to expose real weaknesses in consolidation, retrieval, and temporal grounding. A higher F1 that comes only from a looser eval reader or oracle retrieval is invalid progress.

## When to use this skill

- Running `./benchmarks/local/run_benchmarks.sh` or `benchmarks/local/runners/run.rb`
- Configuring `benchmarks/local/benchmarks.env` (LM Studio model id, dataset roots)
- Interpreting `benchmarks/local/results/*.json`
- Choosing variant (`classic`, `zero_mem_full`) or smoke limits

For **changing adapters, harness, scorers, or product fixes suggested by bench failures**, use **llmemory-benchmarks-dev**.

## Quick run

```bash
./benchmarks/local/run_benchmarks.sh smoke          # fixtures, no LM Studio
./benchmarks/local/run_benchmarks.sh check            # LM Studio /v1/models
./benchmarks/local/run_benchmarks.sh run locomo --limit 20 --variant classic
```

Config: `benchmarks/local/benchmarks.env` — set `LLMEMORY_LLM_MODEL` to the exact id from LM Studio. Template: `benchmarks.env.example`.

Docs: [benchmarks/local/README.md](../../../benchmarks/local/README.md)

## Interpreting results

Read **`bench_scores`** (e.g. LoCoMo F1) together with per-row fields:

- **`prediction`** vs **`gold_answer`**
- **`localization`** (recall@k, MRR) — is evidence in retrieved context?
- **`cost.invoke_calls_delta`** on query — classic retrieve often 0 for short questions (no query expansion LLM)

Low F1 with **"I don't know"** and good gold text only in dialogue often means:

1. **Retrieve** did not surface the right fact/turn (product issue).
2. **Temporal** gold (absolute date) vs relative wording in memory ("yesterday") — product must preserve/use `occurred_at`, not reader hacks.

Local **LLM-as-judge** (`--use-judge`) is not comparable to paper GPT-4o scores.

## Diagnostic

```bash
export LOCOMO_DATASET_ROOT=...   # see benchmarks.env
bundle exec ruby benchmarks/local/diag_locomo.rb
```

Compare `classic` vs `zero_mem_full` retrieval snippets and `gold in ranked top 5?`.

## Datasets

Not vendored in the repo. `LOCOMO_DATASET_ROOT` must point at a checkout with `data/locomo10.json`. Other benches: env vars in README.
