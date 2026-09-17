# Zero-Mem benchmark harness

Repeatable retrieval/answer evaluation for experimental Zero-Mem. This directory is **not** part of the `llmemory` gem API.

## CI (fixtures only)

```bash
bundle exec rspec spec/zero_mem/gates_spec.rb spec/zero_mem/zm0_baseline_spec.rb
```

## Run locally (no network)

```bash
bundle exec ruby benchmarks/zero_mem/runners/classic_baseline.rb
bundle exec ruby benchmarks/zero_mem/runners/ablation.rb
bundle exec ruby benchmarks/zero_mem/runners/sweep.rb
bundle exec ruby benchmarks/zero_mem/runners/cost_frontier.rb
```

Outputs default to `benchmarks/zero_mem/results/*.json` (gitignored except examples).

## Variants

See `variants.rb`: `:classic`, `:zero_mem_full`, ablations (`hierarchy_only`, `graph_only`, `no_closure`, `no_calibration`, `no_planning`).

## External datasets

Adapters under `adapters/` (LoCoMo, HotpotQA, …) require env vars such as `LOCOMO_DATASET_ROOT`. They are **skipped** when unset — never required for CI.

## Reproducibility

- Fixture hashes: `ZeroMem::FixtureLoader.fixture_content_hashes`
- Defaults: `profile.yml` (update after sweeps; keep in sync with `Llmemory.configure`)

## What not to claim

- Numbers here are **not** the Zero-Mem paper results (see [docs/zero_mem_limitations.md](../../docs/zero_mem_limitations.md)).

Operations and storage: [migration/ZERO_MEM.md](../../migration/ZERO_MEM.md). Limitations: [docs/zero_mem_limitations.md](../../docs/zero_mem_limitations.md).
