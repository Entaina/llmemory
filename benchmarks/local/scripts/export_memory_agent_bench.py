#!/usr/bin/env python3
"""Export ai-hyz/MemoryAgentBench parquet splits to JSONL for local adapters."""
import json
import os
import sys
import urllib.request

ROOT = os.environ.get("FETCH_MAB_ROOT", "benchmarks/local/data/MemoryAgentBench")
SUBSETS = [
    "Accurate_Retrieval",
    "FactConsolidation",  # maps to Conflict_Resolution on HF if FactConsolidation missing
]
HF_SUBSET_FILES = {
    "Accurate_Retrieval": "Accurate_Retrieval-00000-of-00001.parquet",
    "FactConsolidation": "Conflict_Resolution-00000-of-00001.parquet",
    "Conflict_Resolution": "Conflict_Resolution-00000-of-00001.parquet",
}


def ensure_pyarrow():
    import pyarrow.parquet as pq  # noqa: F401


def download_parquet(filename: str, dest: str) -> None:
    if os.path.isfile(dest):
        return
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    url = f"https://huggingface.co/datasets/ai-hyz/MemoryAgentBench/resolve/main/data/{filename}"
    print(f"Downloading {url} ...")
    urllib.request.urlretrieve(url, dest)


def export_subset(subset: str) -> None:
    parquet_name = HF_SUBSET_FILES.get(subset)
    if not parquet_name:
        print(f"Skip unknown subset {subset}", file=sys.stderr)
        return

    cache = os.path.join(ROOT, "_cache", parquet_name)
    download_parquet(parquet_name, cache)

    import pyarrow.parquet as pq

    table = pq.read_table(cache)
    rows = table.to_pylist()
    out_dir = os.path.join(ROOT, subset)
    os.makedirs(out_dir, exist_ok=True)
    out_path = os.path.join(out_dir, f"{subset.lower()}.jsonl")

    with open(out_path, "w", encoding="utf-8") as f:
        for row in rows:
            f.write(json.dumps(row, ensure_ascii=False) + "\n")

    print(f"Wrote {out_path} ({len(rows)} records)")


def main() -> None:
    ensure_pyarrow()
    os.makedirs(ROOT, exist_ok=True)
    for subset in SUBSETS:
        export_subset(subset)


if __name__ == "__main__":
    main()
