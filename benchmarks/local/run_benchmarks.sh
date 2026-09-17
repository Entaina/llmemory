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

SUITE_DIAG_VARIANTS=(classic zero_mem_full hybrid)

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
  local base="${LLMEMORY_LLM_BASE_URL%/}"
  local url="${base}/models"
  echo "Checking LM Studio at $url ..."
  if ! curl -sf "$url" >/dev/null; then
    echo "ERROR: cannot reach LM Studio. Start the local server in LM Studio (Developer → Local Server)." >&2
    exit 1
  fi
  echo "OK. Model: ${LLMEMORY_LLM_MODEL} (profile: ${LLMEMORY_BENCH_PROFILE})"
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
  suite-diag        Diagnostic limits × classic, zero_mem_full, hybrid (needs LM Studio)

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
  run_ruby \
    --bench "$bench" \
    --reader llm \
    --out "$out" \
    "$@"
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

cmd_suite_diag() {
  load_env
  cmd_smoke 5
  apply_lmstudio_defaults
  check_lmstudio
  local bench limit variant run_ts
  run_ts="${TIMESTAMP}"
  for bench in "${BENCHES[@]}"; do
    [[ "$bench" == "fixtures" ]] && continue
    if ! bench_dataset_ready "$bench"; then
      echo "Skip $bench (dataset env not set)"
      continue
    fi
    limit="$(smoke_limit_for "$bench")"
    for variant in "${SUITE_DIAG_VARIANTS[@]}"; do
      echo "=== suite-diag: $bench variant=$variant (limit=$limit) ==="
      export LLMEMORY_BENCH_OUT="$RESULTS_DIR/${bench}__${variant}__${run_ts}.json"
      cmd_run "$bench" --limit "$limit" --variant "$variant" \
        || echo "WARN: $bench $variant run failed"
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
    *)
      echo "Unknown command: $cmd" >&2
      cmd_help
      exit 1
      ;;
  esac
}

main "$@"
