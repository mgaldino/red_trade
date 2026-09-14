#!/usr/bin/env python3
"""Run the second, technically distinct mbl.is access diagnostic.

The probe uses an installed Chromium-family browser in headless mode and saves
the returned DOM. It does not solve challenges, log in, or access article
bodies. Its output is diagnostic only and is never promoted into records.csv.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import shutil
import subprocess
import tempfile
from datetime import datetime, timezone
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parents[2]
CHROME_CANDIDATES = [
    Path("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"),
    Path("/Applications/Chromium.app/Contents/MacOS/Chromium"),
]


def find_browser() -> Path | None:
    for path in CHROME_CANDIDATES:
        if path.is_file():
            return path
    for command in ("google-chrome", "chromium", "chromium-browser"):
        resolved = shutil.which(command)
        if resolved:
            return Path(resolved)
    return None


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, default=SCRIPT_DIR / "pilot_config.json")
    args = parser.parse_args()
    with args.config.open(encoding="utf-8") as handle:
        config = json.load(handle)
    source = next(item for item in config["sources"] if item["source_id"] == "mbl")
    raw_dir = REPO_ROOT / "data" / "raw" / "media_archive_pilot" / config["run_date"]
    log_path = raw_dir / "mbl_headless_probe.csv"
    if log_path.exists():
        raise FileExistsError(f"Refusing to overwrite {log_path}")
    browser = find_browser()
    fields = [
        "requested_date",
        "requested_url",
        "started_at_utc",
        "completed_at_utc",
        "browser_executable",
        "return_code",
        "outcome",
        "stdout_bytes",
        "stdout_sha256",
        "raw_html_relative_path",
        "stderr_relative_path",
        "challenge_markers",
        "error",
    ]
    rows: list[dict[str, object]] = []
    for requested_date in config["fixed_dates"]:
        year, month, day = requested_date.split("-")
        url = source["daily_template"].format(year=year, month=month, day=day, date=requested_date)
        target_dir = raw_dir / "mbl" / requested_date
        target_dir.mkdir(parents=True, exist_ok=True)
        html_path = target_dir / "headless_probe.html"
        stderr_path = target_dir / "headless_probe.stderr.txt"
        if html_path.exists() or stderr_path.exists():
            raise FileExistsError(f"Refusing to overwrite headless probe for {requested_date}")
        started = utc_now()
        error = ""
        stdout = b""
        stderr = b""
        return_code: int | str = ""
        if browser is None:
            error = "No installed Chromium-family executable found"
        else:
            try:
                with tempfile.TemporaryDirectory(prefix="media-archive-mbl-") as profile:
                    completed = subprocess.run(
                        [
                            str(browser),
                            "--headless=new",
                            "--disable-gpu",
                            "--no-first-run",
                            "--disable-background-networking",
                            f"--user-data-dir={profile}",
                            "--dump-dom",
                            url,
                        ],
                        capture_output=True,
                        timeout=45,
                        check=False,
                    )
                stdout = completed.stdout
                stderr = completed.stderr
                return_code = completed.returncode
            except subprocess.TimeoutExpired as exc:
                stdout = exc.stdout or b""
                stderr = exc.stderr or b""
                error = "Headless browser timed out after 45 seconds"
        with html_path.open("xb") as handle:
            handle.write(stdout)
        with stderr_path.open("xb") as handle:
            handle.write(stderr)
        lowered = stdout.lower()
        markers = [
            marker.decode("ascii")
            for marker in (b"cloudflare", b"just a moment", b"cf-chl", b"challenge-platform")
            if marker in lowered
        ]
        outcome = "challenge" if markers else "page_returned"
        if error:
            outcome = "probe_failure"
        elif not stdout:
            outcome = "empty_response"
        rows.append(
            {
                "requested_date": requested_date,
                "requested_url": url,
                "started_at_utc": started,
                "completed_at_utc": utc_now(),
                "browser_executable": str(browser) if browser else "",
                "return_code": return_code,
                "outcome": outcome,
                "stdout_bytes": len(stdout),
                "stdout_sha256": hashlib.sha256(stdout).hexdigest(),
                "raw_html_relative_path": str(html_path.relative_to(raw_dir)),
                "stderr_relative_path": str(stderr_path.relative_to(raw_dir)),
                "challenge_markers": "|".join(markers),
                "error": error,
            }
        )
    with log_path.open("x", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)
    print(f"mbl.is headless diagnostic complete: {log_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
