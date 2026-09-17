#!/usr/bin/env bash
# Download / clone benchmark exports into benchmarks/local/data/ (gitignored).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
DATA="$ROOT/benchmarks/local/data"
mkdir -p "$DATA"

hf_get() {
  local repo_path="$1"
  local dest="$2"
  mkdir -p "$(dirname "$dest")"
  curl -sfL "https://huggingface.co/datasets/${repo_path}" -o "$dest"
}

clone_if_missing() {
  local url="$1"
  local dir="$2"
  if [[ -d "$dir/.git" ]]; then
    echo "OK (exists): $dir"
  else
    git clone --depth 1 "$url" "$dir"
  fi
}

echo "=== LongMemEval oracle JSON ==="
LME_DATA="$DATA/LongMemEval/data"
mkdir -p "$LME_DATA"
for f in longmemeval_oracle.json longmemeval_s_cleaned.json; do
  dest="$LME_DATA/$f"
  if [[ -f "$dest" ]]; then
    echo "OK: $dest"
  else
    curl -sfL "https://huggingface.co/datasets/xiaowu0162/longmemeval-cleaned/resolve/main/$f" -o "$dest"
    echo "Wrote $dest"
  fi
done

echo "=== Git checkouts ==="
clone_if_missing "https://github.com/XMUDeepLIT/MemSyco-Bench.git" "$DATA/MemSyco-Bench-src"
clone_if_missing "https://github.com/Cantaloupe-M/Mem2ActBench.git" "$DATA/Mem2ActBench-src"
clone_if_missing "https://github.com/xjtuleeyf/Locomo-Plus.git" "$DATA/Locomo-Plus-src"

# Symlink / copy expected layout for adapters
if [[ -d "$DATA/MemSyco-Bench-src/data" ]]; then
  rm -rf "$DATA/MemSyco-Bench"
  ln -sfn "$(realpath "$DATA/MemSyco-Bench-src/data")" "$DATA/MemSyco-Bench" 2>/dev/null || cp -a "$DATA/MemSyco-Bench-src/data" "$DATA/MemSyco-Bench"
fi

MEM2ACT_QA=""
for candidate in \
  "$DATA/Mem2ActBench-src/qa_dataset.jsonl" \
  "$DATA/Mem2ActBench-src/Mem2ActBench/qa_dataset.jsonl" \
  "$DATA/Mem2ActBench-src/toolmembench_small/qa_dataset.jsonl"; do
  if [[ -f "$candidate" ]]; then
    MEM2ACT_QA="$candidate"
    break
  fi
done
if [[ -n "$MEM2ACT_QA" ]]; then
  rm -rf "$DATA/Mem2ActBench"
  mkdir -p "$DATA/Mem2ActBench"
  cp -a "$MEM2ACT_QA" "$DATA/Mem2ActBench/qa_dataset.jsonl"
  echo "Mem2Act: $DATA/Mem2ActBench/qa_dataset.jsonl"
else
  echo "WARN: Mem2Act qa_dataset.jsonl not found" >&2
fi

if [[ -d "$DATA/Locomo-Plus-src" ]]; then
  rm -rf "$DATA/Locomo-Plus"
  # Prefer data/ subfolder if present
  if [[ -d "$DATA/Locomo-Plus-src/data" ]]; then
    ln -sfn "$(realpath "$DATA/Locomo-Plus-src/data")" "$DATA/Locomo-Plus" 2>/dev/null || cp -a "$DATA/Locomo-Plus-src/data" "$DATA/Locomo-Plus"
  else
    ln -sfn "$(realpath "$DATA/Locomo-Plus-src")" "$DATA/Locomo-Plus" 2>/dev/null || cp -a "$DATA/Locomo-Plus-src" "$DATA/Locomo-Plus"
  fi
fi

echo "=== MemoryArena JSONL (HF) ==="
ARENA="$DATA/memoryarena"
mkdir -p "$ARENA"
for cfg in bundled_shopping progressive_search group_travel_planner formal_reasoning_math formal_reasoning_phys; do
  dest="$ARENA/${cfg}.jsonl"
  if [[ -f "$dest" ]]; then
    echo "OK: $dest"
    continue
  fi
  url="https://huggingface.co/datasets/ZexueHe/memoryarena/resolve/main/${cfg}/data.jsonl"
  if curl -sfL "$url" -o "$dest"; then
    echo "Wrote $dest"
  else
    echo "WARN: failed $cfg" >&2
    rm -f "$dest"
  fi
done

echo "=== MemoryAgentBench (parquet → JSONL via Python) ==="
export FETCH_MAB_ROOT="$DATA/MemoryAgentBench"
VENV="$ROOT/benchmarks/local/scripts/.venv-bench-fetch"
if [[ ! -x "$VENV/bin/python" ]]; then
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install -q pyarrow
fi
"$VENV/bin/python" "$ROOT/benchmarks/local/scripts/export_memory_agent_bench.py"

echo "Done. Verify with:"
echo "  source benchmarks/local/benchmarks.env"
echo "  bundle exec ruby -r./benchmarks/local/registry -e \"...\""
