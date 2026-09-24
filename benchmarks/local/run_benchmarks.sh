#!/usr/bin/env bash
# Launch llmemory local memory benchmarks (LM Studio or deterministic smoke).
#
# Usage:
#   ./benchmarks/local/run_benchmarks.sh help
#   ./benchmarks/local/run_benchmarks.sh check
#   ./benchmarks/local/run_benchmarks.sh smoke
#   ./benchmarks/local/run_benchmarks.sh run locomo --limit 20
#   ./benchmarks/local/run_benchmarks.sh suite-smoke
#
# Optional: copy benchmarks/local/benchmarks.env.example → benchmarks/local/benchmarks.env

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

ENV_FILE="${LLMEMORY_BENCH_ENV:-benchmarks/local/benchmarks.env}"
RUNNER=(bundle exec ruby benchmarks/local/runners/run.rb)
RESULTS_DIR="benchmarks/local/results"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"

BENCHES=(
  fixtures
  locomo
  longmemeval
  memoryagentbench
  locomo_plus
  memsyco
  groupmembench
  mem2act
  memory_arena
)

# Override: SUITE_DIAG_VARIANTS="hybrid" (space-separated)
if [[ -n "${SUITE_DIAG_VARIANTS:-}" ]]; then
  read -ra SUITE_DIAG_VARIANTS <<< "${SUITE_DIAG_VARIANTS}"
else
  SUITE_DIAG_VARIANTS=(classic zero_mem_full hybrid)
fi
# Default suite excludes memory_arena (needs arena_match scorer, not substring EM on JSON gold).
SUITE_DIAG_BENCHES="${SUITE_DIAG_BENCHES:-fixtures locomo longmemeval memoryagentbench locomo_plus memsyco groupmembench mem2act}"

load_env() {
  if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    set -a
    source "$ENV_FILE"
    set +a
    echo "Loaded $ENV_FILE"
  fi
}

profile_model_hint() {
  local profile="${LLMEMORY_BENCH_PROFILE:-default}"
  bundle exec ruby -ryaml -e "
    p = YAML.load_file('benchmarks/local/models.yml').dig('profiles', '${profile}')
    abort('Unknown profile ${profile}') unless p
    puts p['llm_model']
  " 2>/dev/null || true
}

apply_lmstudio_defaults() {
  export LLMEMORY_BENCH_PROFILE="${LLMEMORY_BENCH_PROFILE:-default}"
  export LLMEMORY_LLM_BASE_URL="${LLMEMORY_LLM_BASE_URL:-http://127.0.0.1:1234/v1}"
  export LLMEMORY_LLM_API_KEY="${LLMEMORY_LLM_API_KEY:-lm-studio}"
  export LLMEMORY_LLM_TIMEOUT="${LLMEMORY_LLM_TIMEOUT:-600}"
  export LLMEMORY_LLM_HTTP_RETRIES="${LLMEMORY_LLM_HTTP_RETRIES:-4}"

  if [[ -z "${LLMEMORY_LLM_MODEL:-}" ]]; then
    hint="$(profile_model_hint)"
    if [[ -n "$hint" ]]; then
      export LLMEMORY_LLM_MODEL="$hint"
      echo "LLMEMORY_LLM_MODEL not set; using profile hint: $LLMEMORY_LLM_MODEL"
      echo "  (Must match the model id shown in LM Studio → Server → Loaded models)"
    else
      echo "ERROR: set LLMEMORY_LLM_MODEL to your LM Studio model id." >&2
      exit 1
    fi
  fi
}

check_lmstudio() {
  apply_lmstudio_defaults
  echo "Checking LM Studio (models + chat completion) ..."
  bundle exec ruby -e '
    require_relative "benchmarks/local/lm_studio"
    LocalBenchmark::LmStudio.apply_profile!
    LocalBenchmark::LmStudio.health_check!
  ' || {
    echo "ERROR: LM Studio check failed. Restart server, load ${LLMEMORY_LLM_MODEL}, then retry." >&2
    exit 1
  }
}

run_ruby() {
  "${RUNNER[@]}" "$@"
}

cmd_help() {
  cat <<EOF
llmemory local benchmarks (LM Studio)

Commands:
  help              This message
  check             Verify LM Studio /v1/models is up
  smoke             Fixtures only, no LM Studio (deterministic reader)
  run BENCH [OPTS]  One benchmark with LM Studio (--reader llm)
  suite-smoke       Run smoke limits on every bench that has dataset env set
  suite-diag        Diagnostic limits × variants (needs LM Studio; prefer step)
  step BENCH        Hybrid mini slice (fix issues before scaling up)
  step-cycle        smoke + all hybrid steps + summarize_cycle.rb
  step-plan         Print recommended step order (hybrid only)
  baseline          Reference run (LoCoMo×3, LongMemEval×3, hybrid on other benches)
  baseline-control-7b  Hybrid LoCoMo slice with LLMEMORY_LLM_MODEL_CONTROL (default qwen2.5-7b-instruct)

Environment (see benchmarks/local/benchmarks.env.example):
  LLMEMORY_BENCH_PROFILE   smoke | default | quality
  LLMEMORY_LLM_BASE_URL    http://127.0.0.1:1234/v1
  LLMEMORY_LLM_MODEL       exact id from LM Studio
  LOCOMO_DATASET_ROOT      path to snap-research/locomo clone
  LONGMEMEVAL_DATASET_ROOT path with longmemeval_oracle.json
  ... (full list in benchmarks/local/README.md)

Examples:
  ./benchmarks/local/run_benchmarks.sh smoke
  export LLMEMORY_LLM_MODEL='qwen2.5-7b-instruct'
  ./benchmarks/local/run_benchmarks.sh check
  ./benchmarks/local/run_benchmarks.sh run locomo --limit 20 --variant classic
  LOCOMO_DATASET_ROOT=~/data/locomo ./benchmarks/local/run_benchmarks.sh suite-smoke

LM Studio quick start:
  1. Download an instruct model (e.g. Qwen2.5-7B-Instruct) in LM Studio
  2. Load the model → Start server (port 1234, OpenAI-compatible API)
  3. Copy the model id from the server UI into LLMEMORY_LLM_MODEL
  4. ./benchmarks/local/run_benchmarks.sh check && ./benchmarks/local/run_benchmarks.sh run locomo --limit 10

Benches: ${BENCHES[*]}
EOF
}

cmd_smoke() {
  mkdir -p "$RESULTS_DIR"
  run_ruby \
    --bench fixtures \
    --limit "${1:-5}" \
    --reader deterministic \
    --skip-health \
    --out "$RESULTS_DIR/smoke_fixtures_${TIMESTAMP}.json"
}

cmd_run() {
  if [[ $# -lt 1 ]]; then
    echo "Usage: $0 run BENCH [--limit N] [--variant classic] [--use-judge] ..." >&2
    exit 1
  fi
  local bench="$1"
  shift
  apply_lmstudio_defaults
  mkdir -p "$RESULTS_DIR"
  local out="${LLMEMORY_BENCH_OUT:-$RESULTS_DIR/${bench}_${TIMESTAMP}.json}"
  local timeout_secs="${SUITE_DIAG_BENCH_TIMEOUT:-3600}"
  timeout "$timeout_secs" "${RUNNER[@]}" \
    --bench "$bench" \
    --reader llm \
    --out "$out" \
    "$@" \
    || {
      ec=$?
      if [[ $ec -eq 124 ]]; then
        echo "WARN: bench $bench timed out after ${timeout_secs}s" >&2
        exit 124
      fi
      exit "$ec"
    }
}

bench_dataset_ready() {
  local bench="$1"
  case "$bench" in
    fixtures) return 0 ;;
    locomo) [[ -n "${LOCOMO_DATASET_ROOT:-}" ]] ;;
    longmemeval) [[ -n "${LONGMEMEVAL_DATASET_ROOT:-}" ]] ;;
    memoryagentbench) [[ -n "${MEMORYAGENTBENCH_DATASET_ROOT:-}" ]] ;;
    locomo_plus) [[ -n "${LOCOMO_PLUS_DATASET_ROOT:-}" ]] ;;
    memsyco) [[ -n "${MEMSYCO_DATASET_ROOT:-}" ]] ;;
    groupmembench) [[ -n "${GROUPMEMBENCH_DATASET_ROOT:-}" ]] ;;
    mem2act) [[ -n "${MEM2ACT_DATASET_ROOT:-}" ]] ;;
    memory_arena) [[ -n "${MEMORYARENA_DATASET_ROOT:-}" ]] ;;
    *) return 1 ;;
  esac
}

smoke_limit_for() {
  case "$1" in
    fixtures) echo 5 ;;
    locomo) echo 20 ;;
    longmemeval) echo 10 ;;
    memoryagentbench) echo 20 ;;
    locomo_plus|memsyco|mem2act) echo 20 ;;
    groupmembench) echo 10 ;;
    memory_arena) echo 5 ;;
    *) echo 10 ;;
  esac
}

cmd_suite_smoke() {
  load_env
  cmd_smoke 5
  apply_lmstudio_defaults
  check_lmstudio
  local bench limit
  for bench in "${BENCHES[@]}"; do
    [[ "$bench" == "fixtures" ]] && continue
    if ! bench_dataset_ready "$bench"; then
      echo "Skip $bench (dataset env not set)"
      continue
    fi
    limit="$(smoke_limit_for "$bench")"
    echo "=== suite-smoke: $bench (limit=$limit) ==="
    cmd_run "$bench" --limit "$limit" --variant classic || echo "WARN: $bench run failed"
  done
  echo "Done. Results in $RESULTS_DIR/"
}

suite_diag_use_judge() {
  local bench="$1"
  [[ "${SUITE_DIAG_JUDGE:-1}" == "1" ]] || return 1
  case "$bench" in
    longmemeval|memsyco|locomo_plus) return 0 ;;
    *) return 1 ;;
  esac
}

bench_in_suite_diag() {
  local bench="$1"
  [[ " $SUITE_DIAG_BENCHES " == *" $bench "* ]]
}

apply_hybrid_step_env() {
  export LLMEMORY_BENCH_CACHE="${LLMEMORY_BENCH_CACHE:-1}"
  export LLMEMORY_LLM_TEMPERATURE="${LLMEMORY_LLM_TEMPERATURE:-0}"
  export LLMEMORY_BENCH_SEED="${LLMEMORY_BENCH_SEED:-step}"
  export MEMORYAGENTBENCH_MAX_SESSIONS="${MEMORYAGENTBENCH_MAX_SESSIONS:-40}"
  export GROUPMEMBENCH_MAX_TURNS="${GROUPMEMBENCH_MAX_TURNS:-120}"
  export STEP_MAX_SESSIONS="${STEP_MAX_SESSIONS:-2}"
  export LOCOMO_MAX_SESSIONS="${LOCOMO_MAX_SESSIONS:-$STEP_MAX_SESSIONS}"
  export LLMEMORY_SUMMARY_REFRESH_EVERY="${LLMEMORY_SUMMARY_REFRESH_EVERY:-9999}"
  export LLMEMORY_BENCH_FAST="${LLMEMORY_BENCH_FAST:-1}"
  export LLMEMORY_BENCH_TRACE="${LLMEMORY_BENCH_TRACE:-1}"
  export LLMEMORY_BENCH_EXTRACT_MAX_CHARS="${LLMEMORY_BENCH_EXTRACT_MAX_CHARS:-1200}"
  export LLMEMORY_LLM_TIMEOUT="${LLMEMORY_BENCH_LLM_TIMEOUT:-300}"
  export LLMEMORY_BENCH_MAX_OUTPUT_TOKENS="${LLMEMORY_BENCH_MAX_OUTPUT_TOKENS:-512}"
  # Optional: LLMEMORY_BENCH_SKIP_CONSOLIDATE=1 to debug retrieve-only (not valid hybrid quality).
  export LLMEMORY_BENCH_SKIP_CONSOLIDATE="${LLMEMORY_BENCH_SKIP_CONSOLIDATE:-0}"
  export SUITE_DIAG_BENCH_TIMEOUT="${STEP_BENCH_TIMEOUT:-900}"
}

cmd_step_plan() {
  cat <<EOF
Hybrid iterative plan (run one step, summarize, fix product/harness, repeat):

  1. ./benchmarks/local/run_benchmarks.sh smoke
  2. ./benchmarks/local/run_benchmarks.sh step locomo
  3. ./benchmarks/local/run_benchmarks.sh step longmemeval
  4. ./benchmarks/local/run_benchmarks.sh step mem2act
  5. ./benchmarks/local/run_benchmarks.sh step memoryagentbench
  6. ./benchmarks/local/run_benchmarks.sh step locomo_plus
  7. ./benchmarks/local/run_benchmarks.sh step memsyco
  8. ./benchmarks/local/run_benchmarks.sh step groupmembench

Tune slice size: STEP_CONVERSATIONS STEP_PER_CONV STEP_LIMIT STEP_BENCH_TIMEOUT
After each JSON: bundle exec ruby benchmarks/local/scripts/summarize_run.rb PATH
Full cycle: ./benchmarks/local/run_benchmarks.sh step-cycle
EOF
}

cmd_step_cycle() {
  load_env
  cmd_smoke 5
  local bench failed=0
  for bench in locomo longmemeval mem2act memoryagentbench locomo_plus memsyco groupmembench; do
    if bench_dataset_ready "$bench"; then
      cmd_step "$bench" || failed=$((failed + 1))
    else
      echo "Skip $bench (dataset env not set)"
    fi
  done
  bundle exec ruby benchmarks/local/scripts/summarize_cycle.rb "$RESULTS_DIR" || true
  return "$failed"
}

cmd_step() {
  local bench="${1:-}"
  shift || true
  if [[ -z "$bench" ]]; then
    echo "Usage: $0 step BENCH [extra run.rb options]" >&2
    echo "       $0 step-plan" >&2
    exit 1
  fi
  apply_lmstudio_defaults
  check_lmstudio
  if ! bench_dataset_ready "$bench"; then
    echo "Skip $bench (dataset env not set)" >&2
    exit 1
  fi

  apply_hybrid_step_env
  mkdir -p "$RESULTS_DIR"
  local out="${LLMEMORY_BENCH_OUT:-$RESULTS_DIR/${bench}__hybrid__step_${TIMESTAMP}.json}"
  local extra=(--variant hybrid)
  case "$bench" in
    locomo)
      export SUITE_DIAG_BENCH_TIMEOUT="${STEP_BENCH_TIMEOUT:-1800}"
      extra+=(
        --stratify category
        --conversations "${STEP_CONVERSATIONS:-1}"
        --per-conversation "${STEP_PER_CONV:-4}"
        --seed "${LLMEMORY_BENCH_SEED}"
      )
      if [[ "${LLMEMORY_BENCH_SKIP_CONSOLIDATE}" == "1" ]]; then
        echo "LoCoMo step: ${LOCOMO_MAX_SESSIONS} sessions, ${STEP_PER_CONV:-4} queries (traces only, skip consolidate LLM)"
      else
        echo "LoCoMo step: ${LOCOMO_MAX_SESSIONS} sessions, ${STEP_PER_CONV:-4} queries (consolidate per session)"
      fi
      ;;
    longmemeval)
      extra+=(
        --stratify question_type
        --limit "${STEP_LIMIT:-3}"
        --use-judge
        --seed "${LLMEMORY_BENCH_SEED}"
      )
      ;;
    locomo_plus)
      export STEP_MAX_SESSIONS="${LOCOMO_PLUS_MAX_SESSIONS:-4}"
      export LOCOMO_MAX_SESSIONS="$STEP_MAX_SESSIONS"
      extra+=(--limit "${STEP_LIMIT:-5}" --use-judge)
      ;;
    memsyco)
      export MEMSYCO_TASK="${MEMSYCO_TASK:-all}"
      extra+=(--limit "${STEP_LIMIT:-5}" --use-judge)
      ;;
    groupmembench)
      export SUITE_DIAG_BENCH_TIMEOUT="${STEP_BENCH_TIMEOUT:-2400}"
      export GROUPMEMBENCH_MAX_TURNS="${GROUPMEMBENCH_MAX_TURNS:-120}"
      extra+=(--limit "${STEP_LIMIT:-3}")
      ;;
    *)
      extra+=(--limit "${STEP_LIMIT:-5}")
      ;;
  esac

  local trace_log="$RESULTS_DIR/step_trace_${TIMESTAMP}.log"
  export LLMEMORY_BENCH_TRACE_FILE="$trace_log"
  echo "=== step: $bench hybrid (out=$out) trace=$trace_log ==="
  export LLMEMORY_BENCH_OUT="$out"
  if cmd_run "$bench" "${extra[@]}" "$@"; then
    unset LLMEMORY_BENCH_OUT LLMEMORY_BENCH_TRACE_FILE
    echo "Summarize: bundle exec ruby benchmarks/local/scripts/summarize_run.rb $out"
    bundle exec ruby benchmarks/local/scripts/summarize_run.rb "$out" || true
  else
    unset LLMEMORY_BENCH_OUT LLMEMORY_BENCH_TRACE_FILE
    echo "Trace log (even on timeout): $trace_log" >&2
    [[ -f "$trace_log" ]] && tail -30 "$trace_log" >&2
    return 1
  fi
}

cmd_baseline() {
  load_env
  apply_lmstudio_defaults
  check_lmstudio
  export LLMEMORY_BENCH_CACHE="${LLMEMORY_BENCH_CACHE:-1}"
  export LLMEMORY_LLM_TEMPERATURE="${LLMEMORY_LLM_TEMPERATURE:-0}"
  export LLMEMORY_BENCH_SEED="${LLMEMORY_BENCH_SEED:-baseline}"
  export MEMSYCO_TASK="${MEMSYCO_TASK:-all}"
  local variant run_ts="${TIMESTAMP}"
  for variant in classic zero_mem_full hybrid; do
    echo "=== baseline: locomo variant=$variant ==="
    export LLMEMORY_BENCH_OUT="$RESULTS_DIR/locomo__${variant}__baseline_${run_ts}.json"
    cmd_run locomo --variant "$variant" \
      --stratify category --conversations 3 --per-conversation 8 \
      --seed baseline --reader llm \
      || echo "WARN: locomo $variant baseline failed"
    unset LLMEMORY_BENCH_OUT
  done
  for variant in classic zero_mem_full hybrid; do
    echo "=== baseline: longmemeval variant=$variant ==="
    export LLMEMORY_BENCH_OUT="$RESULTS_DIR/longmemeval__${variant}__baseline_${run_ts}.json"
    cmd_run longmemeval --variant "$variant" \
      --stratify question_type --limit 15 --use-judge --seed baseline \
      || echo "WARN: longmemeval $variant baseline failed"
    unset LLMEMORY_BENCH_OUT
  done
  local bench limit
  for bench in memoryagentbench mem2act locomo_plus memsyco groupmembench; do
    bench_dataset_ready "$bench" || continue
    limit=10
    [[ "$bench" == "mem2act" ]] && limit=20
    echo "=== baseline: $bench hybrid ==="
    export LLMEMORY_BENCH_OUT="$RESULTS_DIR/${bench}__hybrid__baseline_${run_ts}.json"
    extra=(--variant hybrid --limit "$limit" --seed baseline)
    [[ "$bench" == "longmemeval" || "$bench" == "memsyco" || "$bench" == "locomo_plus" ]] && extra+=(--use-judge)
    cmd_run "$bench" "${extra[@]}" || echo "WARN: $bench baseline failed"
    unset LLMEMORY_BENCH_OUT
  done
  echo "Baseline tag: baseline_${run_ts}"
}

cmd_baseline_control_7b() {
  load_env
  apply_lmstudio_defaults
  check_lmstudio
  local model="${LLMEMORY_LLM_MODEL_CONTROL:-qwen2.5-7b-instruct}"
  export LLMEMORY_LLM_MODEL="$model"
  export LLMEMORY_BENCH_CACHE_DIR="${LLMEMORY_BENCH_CACHE_DIR:-benchmarks/local/cache/control_7b}"
  export LLMEMORY_BENCH_CACHE="${LLMEMORY_BENCH_CACHE:-1}"
  export LLMEMORY_BENCH_SEED="${LLMEMORY_BENCH_SEED:-baseline-control}"
  local run_ts="${TIMESTAMP}"
  echo "=== baseline control (hybrid, model=$model) ==="
  export LLMEMORY_BENCH_OUT="$RESULTS_DIR/locomo__hybrid__baseline_control_${run_ts}.json"
  cmd_run locomo --variant hybrid \
    --stratify category --conversations 3 --per-conversation 8 \
    --seed baseline-control --reader llm \
    || echo "WARN: control locomo failed"
  unset LLMEMORY_BENCH_OUT LLMEMORY_BENCH_CACHE_DIR
}

cmd_suite_diag() {
  load_env
  cmd_smoke 5
  apply_lmstudio_defaults
  check_lmstudio
  local bench limit variant run_ts extra_args
  run_ts="${TIMESTAMP}"
  for bench in $SUITE_DIAG_BENCHES; do
    [[ "$bench" == "fixtures" ]] && continue
    if ! bench_dataset_ready "$bench"; then
      echo "Skip $bench (dataset env not set)"
      continue
    fi
    limit="$(smoke_limit_for "$bench")"
    for variant in "${SUITE_DIAG_VARIANTS[@]}"; do
      echo "=== suite-diag: $bench variant=$variant (limit=$limit) ==="
      export LLMEMORY_BENCH_OUT="$RESULTS_DIR/${bench}__${variant}__${run_ts}.json"
      export LLMEMORY_BENCH_CACHE="${LLMEMORY_BENCH_CACHE:-1}"
      export LLMEMORY_LLM_TEMPERATURE="${LLMEMORY_LLM_TEMPERATURE:-0}"
      export LLMEMORY_BENCH_SEED="${LLMEMORY_BENCH_SEED:-suite-diag}"
      extra_args=()
      if suite_diag_use_judge "$bench"; then
        extra_args+=(--use-judge)
      fi
      if [[ "$bench" == "memsyco" ]]; then
        export MEMSYCO_TASK="${MEMSYCO_TASK:-all}"
      fi
      case "$bench" in
        locomo)
          extra_args+=(--stratify category --conversations 3 --per-conversation 8 --seed "${LLMEMORY_BENCH_SEED}")
          ;;
        longmemeval)
          extra_args+=(--stratify question_type --limit 10 --seed "${LLMEMORY_BENCH_SEED}")
          ;;
        memsyco)
          extra_args+=(--limit "${MEMSYCO_SUITE_LIMIT:-10}" --seed "${LLMEMORY_BENCH_SEED}")
          ;;
        *)
          extra_args+=(--limit "$limit")
          ;;
      esac
      cmd_run "$bench" --variant "$variant" "${extra_args[@]}" \
        || echo "WARN: $bench $variant run failed (timeout or error)"
      unset LLMEMORY_BENCH_OUT
    done
  done
  bundle exec ruby benchmarks/local/suite_diag.rb "$RESULTS_DIR" "$run_ts"
  echo "Done. Results in $RESULTS_DIR/ (compare suite_diag_${run_ts}.json)"
}

main() {
  local cmd="${1:-help}"
  shift || true
  load_env

  case "$cmd" in
    help|-h|--help) cmd_help ;;
    check) check_lmstudio ;;
    smoke) cmd_smoke "${1:-5}" ;;
    run) cmd_run "$@" ;;
    suite-smoke) cmd_suite_smoke ;;
    suite-diag) cmd_suite_diag ;;
  baseline) cmd_baseline ;;
  baseline-control-7b) cmd_baseline_control_7b ;;
    step-plan) cmd_step_plan ;;
    step-cycle) cmd_step_cycle ;;
    step) cmd_step "$@" ;;
    *)
      echo "Unknown command: $cmd" >&2
      cmd_help
      exit 1
      ;;
  esac
}

main "$@"
