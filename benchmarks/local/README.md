# Local memory benchmarks (LM Studio)

Run standard memory benchmarks against `llmemory` using a **local OpenAI-compatible server** (LM Studio). No paid API tokens required.

Agent guidance: project skills **llmemory-benchmarks** (run/interpret) and **llmemory-benchmarks-dev** (extend bench + product-first rules) in `.cursor/skills/`.

## Launcher script (recommended)

```bash
chmod +x benchmarks/local/run_benchmarks.sh   # once

./benchmarks/local/run_benchmarks.sh help
./benchmarks/local/run_benchmarks.sh smoke                    # no LM Studio
./benchmarks/local/run_benchmarks.sh check                    # LM Studio up?
./benchmarks/local/run_benchmarks.sh run locomo --limit 20    # one bench
```

Config file (model id + datasets): **`benchmarks/local/benchmarks.env`** (not in repo root).

Template: **`benchmarks/local/benchmarks.env.example`**. Copy once if you do not have `benchmarks.env` yet:

```bash
cp benchmarks/local/benchmarks.env.example benchmarks/local/benchmarks.env
```

## Prerequisites

1. LM Studio: enable **Local Server** (default `http://127.0.0.1:1234/v1`).
2. Load a chat model matching `benchmarks/local/models.yml` profile (override with `LLMEMORY_LLM_MODEL`).
3. **Context length:** set loaded context to **≥ 8192** (LoCoMo consolidates per session; 4096 often fails on long sessions). In LM Studio: model load settings → increase context window.
3. Download official datasets into local paths (not vendored in this repo).

## Quick smoke (fixtures, no LM Studio)

```bash
./benchmarks/local/run_benchmarks.sh smoke
# or:
bundle exec ruby benchmarks/local/runners/run.rb --bench fixtures --limit 5 --reader deterministic
```

## LoCoMo smoke (requires dataset)

```bash
git clone https://github.com/snap-research/locomo.git /path/to/locomo
export LOCOMO_DATASET_ROOT=/path/to/locomo
export LLMEMORY_LLM_MODEL='your-model-id'
bundle exec ruby benchmarks/local/runners/run.rb --bench locomo --limit 20 --reader llm
```

## Environment

| Variable | Purpose |
|----------|---------|
| `LLMEMORY_BENCH_PROFILE` | `smoke` / `default` / `quality` (`models.yml`) |
| `LLMEMORY_LLM_BASE_URL` | Default `http://127.0.0.1:1234/v1` |
| `LLMEMORY_LLM_MODEL` | Model id from LM Studio |
| `LLMEMORY_LLM_API_KEY` | Dummy key (default `lm-studio`) |
| `LLMEMORY_SKIP_HEALTH_CHECK` | `1` to skip `/v1/models` |
| `LOCOMO_DATASET_ROOT` | snap-research/locomo checkout |
| `LONGMEMEVAL_DATASET_ROOT` | LongMemEval `data/` with JSON splits |
| `LONGMEMEVAL_SPLIT` | `oracle` (default), `s`, `s_legacy` |
| `MEMORYAGENTBENCH_DATASET_ROOT` | Exported JSON/JSONL |
| `MEMORYAGENTBENCH_SUBSET` | `Accurate_Retrieval` or `FactConsolidation` |
| `LOCOMO_PLUS_DATASET_ROOT` | LoCoMo-Plus data |
| `MEMSYCO_DATASET_ROOT` | MemSyco-Bench JSONL |
| `MEMSYCO_TASK` | Task file stem |
| `GROUPMEMBENCH_DATASET_ROOT` | GroupMemBench checkout |
| `MEM2ACT_DATASET_ROOT` | Mem2ActBench with `qa_dataset.jsonl` |
| `MEMORYARENA_DATASET_ROOT` | MemoryArena JSONL exports |

## Benches

`fixtures`, `locomo`, `longmemeval`, `memoryagentbench`, `locomo_plus`, `memsyco`, `groupmembench`, `mem2act`, `memory_arena`

Variants: `classic`, `zero_mem_full`, `hybrid` (trace ingest + consolidate + fused `Memory#retrieve`).

```bash
bundle exec ruby benchmarks/local/runners/run.rb --bench longmemeval --variant hybrid --limit 10 --reader llm
./benchmarks/local/run_benchmarks.sh suite-diag   # all configured datasets × 3 variants (diagnostic limits)
```

### Dataset checkout (local, gitignored under `benchmarks/local/data/`)

| Bench | Clone / export | Env var | Verify |
|-------|----------------|---------|--------|
| locomo | `git clone https://github.com/snap-research/locomo.git` | `LOCOMO_DATASET_ROOT` → repo root | `test -f $LOCOMO_DATASET_ROOT/data/locomo10.json` |
| longmemeval | `git clone https://github.com/xiaowu0162/LongMemEval.git` | `LONGMEMEVAL_DATASET_ROOT` → `LongMemEval/data` | `test -f .../longmemeval_oracle.json` |
| memoryagentbench | HF / project export into subset dir | `MEMORYAGENTBENCH_DATASET_ROOT` | JSON/JSONL under `Accurate_Retrieval/` |
| locomo_plus | LoCoMo-Plus project data | `LOCOMO_PLUS_DATASET_ROOT` | `*.json` under root |
| memsyco | MemSyco-Bench JSONL | `MEMSYCO_DATASET_ROOT` | `{MEMSYCO_TASK}.jsonl` |
| groupmembench | `git clone https://github.com/UCSB-NLP-Chang/GroupMemBench.git` | `GROUPMEMBENCH_DATASET_ROOT` | channel + `questions/Finance/multi_hop.jsonl` |
| mem2act | Mem2ActBench (`qa_dataset.jsonl`) | `MEM2ACT_DATASET_ROOT` | `test -f .../qa_dataset.jsonl` |
| memory_arena | MemoryArena JSONL export | `MEMORYARENA_DATASET_ROOT` | `{MEMORYARENA_CONFIG}.jsonl` |

See [`benchmarks/local/data/README.md`](data/README.md) or run `./benchmarks/local/scripts/fetch_benchmark_exports.sh` for one-shot setup.

Results default to `benchmarks/local/results/run.json` (gitignored).

## Troubleshooting local runs

- **`Net::ReadTimeout` / `WARN: … classic run failed`**: Variants with `consolidate!` (classic, hybrid) call the LLM many times per LoCoMo/LongMemEval session. On a local 4B model, raise timeouts in `benchmarks.env`:
  - `LLMEMORY_LLM_TIMEOUT=600` (or higher)
  - `LLMEMORY_LLM_HTTP_RETRIES=4`
- **`zero_mem_full` succeeds but classic/hybrid abort**: Same cause — zero_mem skips generative consolidate.
- Re-run a failed cell: `./benchmarks/local/run_benchmarks.sh run locomo --limit 20 --variant classic`

## Honesty

- **LoCoMo F1** uses the official token-F1 protocol (local stem approximation).
- **LLM-as-judge** (`--use-judge`) uses the **same local model**; scores are **not** comparable to GPT-4o paper numbers.
- **MemoryArena v1** evaluates interdependent subtasks as persistent QA, not the full web gym.
