#!/usr/bin/env bash
# Re-run suite-diag cells that failed in the first pass (timeouts + fixed adapter/calibrator bugs).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"
if ! bundle check >/dev/null 2>&1; then
  echo "Installing gems (bundle install)..."
  bundle install
fi
source benchmarks/local/benchmarks.env 2>/dev/null || true
export LLMEMORY_BENCH_ENV="${LLMEMORY_BENCH_ENV:-benchmarks/local/benchmarks.env}"
# shellcheck disable=SC1090
source "$LLMEMORY_BENCH_ENV"

RUN_TS="${RUN_TS:-$(date -u +%Y%m%dT%H%M%SZ)}"
LOG="benchmarks/local/results/suite_diag_rerun_${RUN_TS}.log"
mkdir -p benchmarks/local/results

run_one() {
  local bench="$1" variant="$2" limit="$3"
  echo "=== rerun: $bench variant=$variant limit=$limit ===" | tee -a "$LOG"
  export LLMEMORY_BENCH_OUT="benchmarks/local/results/${bench}__${variant}__${RUN_TS}.json"
  if ./benchmarks/local/run_benchmarks.sh run "$bench" --limit "$limit" --variant "$variant" >>"$LOG" 2>&1; then
    echo "OK: $bench $variant" | tee -a "$LOG"
  else
    echo "WARN: $bench $variant failed" | tee -a "$LOG"
  fi
}

run_one locomo classic 20
run_one locomo hybrid 20
run_one longmemeval classic 10
run_one longmemeval hybrid 10
run_one memoryagentbench classic 20
run_one memoryagentbench zero_mem_full 20
run_one memoryagentbench hybrid 20
run_one memsyco zero_mem_full 20
run_one memsyco hybrid 20

bundle exec ruby benchmarks/local/suite_diag.rb benchmarks/local/results "$RUN_TS" | tee -a "$LOG"
echo "Done rerun TS=$RUN_TS" | tee -a "$LOG"
