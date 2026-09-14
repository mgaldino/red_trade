#!/usr/bin/env python3
"""Create the final checksum manifest after reports and validation exist."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parents[2]


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, default=SCRIPT_DIR / "pilot_config.json")
    args = parser.parse_args()
    with args.config.open(encoding="utf-8") as handle:
        config = json.load(handle)
    raw_dir = REPO_ROOT / "data" / "raw" / "media_archive_pilot" / config["run_date"]
    processed_dir = REPO_ROOT / "data" / "processed" / "media_archive_pilot" / config["run_date"]
    report_dir = REPO_ROOT / "quality_reports" / "media_archive_pilot"
    manifest_path = processed_dir / "file_manifest.csv"
    if manifest_path.exists():
        raise FileExistsError(f"Refusing to overwrite {manifest_path}")
    roots = [SCRIPT_DIR, raw_dir, processed_dir, report_dir]
    paths = sorted(
        {
            path.resolve()
            for root in roots
            for path in root.rglob("*")
            if path.is_file() and path.resolve() != manifest_path.resolve()
        }
    )
    with manifest_path.open("x", encoding="utf-8", newline="") as handle:
        fields = ["relative_path", "bytes", "sha256", "modified_at_utc"]
        writer = csv.DictWriter(handle, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        for path in paths:
            stat = path.stat()
            writer.writerow(
                {
                    "relative_path": str(path.relative_to(REPO_ROOT)),
                    "bytes": stat.st_size,
                    "sha256": sha256_file(path),
                    "modified_at_utc": datetime.fromtimestamp(stat.st_mtime, tz=timezone.utc).isoformat(timespec="seconds"),
                }
            )
    print(f"File manifest contains {len(paths)} files: {manifest_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
