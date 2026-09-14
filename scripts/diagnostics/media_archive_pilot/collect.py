#!/usr/bin/env python3
"""Collect raw metadata responses for the fixed media-archive pilot.

This script only downloads and logs raw responses. Parsing, deduplication and
mention detection live in process.py so that they can be reproduced without
repeating network requests.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import random
import sys
import time
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from typing import Any
from urllib.parse import urlencode, urljoin
from urllib.robotparser import RobotFileParser

import requests
from lxml import html


SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parents[2]
LOG_FIELDS = [
    "request_id",
    "source_id",
    "requested_date",
    "request_role",
    "page_number",
    "requested_url",
    "final_url",
    "requested_at_utc",
    "completed_at_utc",
    "attempts",
    "status_code",
    "outcome",
    "content_type",
    "content_bytes",
    "sha256",
    "raw_relative_path",
    "x_wp_total",
    "x_wp_totalpages",
    "retry_after",
    "error",
]


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_config(path: Path) -> dict[str, Any]:
    with path.open(encoding="utf-8") as handle:
        config = json.load(handle)
    run_date = date.fromisoformat(config["run_date"])
    expected_recent = (run_date.replace(day=1) - timedelta(days=1)).replace(day=15)
    expected_dates = ["2000-06-15", "2009-06-15", "2014-06-15", expected_recent.isoformat()]
    if config["fixed_dates"] != expected_dates:
        raise ValueError(
            f"fixed_dates must be {expected_dates} for run_date={run_date.isoformat()}, "
            f"not {config['fixed_dates']}"
        )
    if len(config["sources"]) != 5:
        raise ValueError("The pilot must contain exactly five final sources.")
    return config


def format_url(template: str, requested_date: str) -> str:
    d = date.fromisoformat(requested_date)
    return template.format(
        date=requested_date,
        year=f"{d.year:04d}",
        month=f"{d.month:02d}",
        day=f"{d.day:02d}",
    )


class RawCollector:
    def __init__(self, config: dict[str, Any], raw_dir: Path) -> None:
        self.config = config
        self.raw_dir = raw_dir
        self.raw_dir.mkdir(parents=True, exist_ok=True)
        self.log_path = raw_dir / "collection_requests.csv"
        self.complete_path = raw_dir / "_COLLECTION_COMPLETE.json"
        if self.complete_path.exists() or self.log_path.exists():
            raise FileExistsError(
                f"Refusing to overwrite an existing collection at {raw_dir}. "
                "Use the saved raw files for reprocessing or choose a new run directory."
            )
        self.session = requests.Session()
        self.session.headers.update(
            {
                "User-Agent": config["http"]["user_agent"],
                "Accept-Language": "en,es,lv,is;q=0.8,*;q=0.5",
            }
        )
        self.timeout = float(config["http"]["timeout_seconds"])
        self.pause = float(config["http"]["pause_seconds"])
        self.max_attempts = int(config["http"]["max_attempts"])
        self.page_cap = int(config["http"]["page_cap"])
        self.request_counter = 0
        with self.log_path.open("x", encoding="utf-8", newline="") as handle:
            csv.DictWriter(handle, fieldnames=LOG_FIELDS).writeheader()

    def _append_log(self, row: dict[str, Any]) -> None:
        with self.log_path.open("a", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=LOG_FIELDS)
            writer.writerow({field: row.get(field, "") for field in LOG_FIELDS})

    def fetch(
        self,
        *,
        source_id: str,
        requested_date: str,
        request_role: str,
        page_number: int | None,
        url: str,
        relative_path: Path,
        headers: dict[str, str] | None = None,
    ) -> tuple[requests.Response | None, dict[str, Any]]:
        destination = self.raw_dir / relative_path
        if destination.exists():
            raise FileExistsError(f"Raw response already exists: {destination}")
        destination.parent.mkdir(parents=True, exist_ok=True)
        self.request_counter += 1
        request_id = f"req_{self.request_counter:04d}"
        started = utc_now()
        response: requests.Response | None = None
        last_error = ""
        attempts = 0
        retryable_statuses = {429, 500, 502, 503, 504}

        for attempt in range(1, self.max_attempts + 1):
            attempts = attempt
            try:
                response = self.session.get(
                    url,
                    timeout=self.timeout,
                    allow_redirects=True,
                    headers=headers,
                )
                if response.status_code not in retryable_statuses or attempt == self.max_attempts:
                    break
                retry_after = response.headers.get("Retry-After", "")
                try:
                    delay = min(float(retry_after), 15.0) if retry_after else self.pause * (2 ** (attempt - 1))
                except ValueError:
                    delay = self.pause * (2 ** (attempt - 1))
                time.sleep(delay + random.uniform(0, 0.25))
            except requests.RequestException as exc:
                last_error = f"{type(exc).__name__}: {exc}"
                if attempt == self.max_attempts:
                    break
                time.sleep(self.pause * (2 ** (attempt - 1)) + random.uniform(0, 0.25))

        content = response.content if response is not None else b""
        if response is not None:
            with destination.open("xb") as handle:
                handle.write(content)
        completed = utc_now()
        status_code = response.status_code if response is not None else ""
        outcome = "success" if response is not None and 200 <= response.status_code < 300 else "http_failure"
        if response is None:
            outcome = "request_failure"
        row = {
            "request_id": request_id,
            "source_id": source_id,
            "requested_date": requested_date,
            "request_role": request_role,
            "page_number": page_number if page_number is not None else "",
            "requested_url": url,
            "final_url": response.url if response is not None else "",
            "requested_at_utc": started,
            "completed_at_utc": completed,
            "attempts": attempts,
            "status_code": status_code,
            "outcome": outcome,
            "content_type": response.headers.get("Content-Type", "") if response is not None else "",
            "content_bytes": len(content) if response is not None else "",
            "sha256": sha256_bytes(content) if response is not None else "",
            "raw_relative_path": str(relative_path) if response is not None else "",
            "x_wp_total": response.headers.get("X-WP-Total", "") if response is not None else "",
            "x_wp_totalpages": response.headers.get("X-WP-TotalPages", "") if response is not None else "",
            "retry_after": response.headers.get("Retry-After", "") if response is not None else "",
            "error": last_error,
        }
        self._append_log(row)
        time.sleep(self.pause)
        return response, row

    def collect_preflight(self, source: dict[str, Any]) -> RobotFileParser | None:
        source_id = source["source_id"]
        robots_response, _ = self.fetch(
            source_id=source_id,
            requested_date="",
            request_role="robots",
            page_number=None,
            url=source["robots_url"],
            relative_path=Path(source_id) / "_preflight" / "robots.txt",
        )
        parser: RobotFileParser | None = None
        if robots_response is not None and robots_response.status_code == 200:
            parser = RobotFileParser()
            parser.set_url(source["robots_url"])
            parser.parse(robots_response.text.splitlines())
        self.fetch(
            source_id=source_id,
            requested_date="",
            request_role="access_conditions",
            page_number=None,
            url=source["conditions_url"],
            relative_path=Path(source_id) / "_preflight" / "conditions.html",
        )
        return parser

    def robots_allows(self, parser: RobotFileParser | None, url: str) -> bool | None:
        if parser is None:
            return None
        return parser.can_fetch(self.config["http"]["user_agent"], url)

    def record_robots_block(self, source_id: str, requested_date: str, url: str) -> None:
        self.request_counter += 1
        self._append_log(
            {
                "request_id": f"req_{self.request_counter:04d}",
                "source_id": source_id,
                "requested_date": requested_date,
                "request_role": "blocked_by_robots",
                "requested_url": url,
                "requested_at_utc": utc_now(),
                "completed_at_utc": utc_now(),
                "attempts": 0,
                "outcome": "robots_disallowed",
                "error": "robots.txt explicitly disallows this URL for the pilot user agent",
            }
        )

    def collect_wordpress(self, source: dict[str, Any], requested_date: str, robots: RobotFileParser | None) -> None:
        target = date.fromisoformat(requested_date)
        previous = target - timedelta(days=1)
        common_params = {
            "after": f"{previous.isoformat()}T23:59:59",
            "before": f"{target.isoformat()}T23:59:59",
            "per_page": "100",
            "orderby": "date",
            "order": "asc",
            "_fields": "id,date,date_gmt,modified,modified_gmt,link,slug,title",
        }
        base_url = source["api_template"]
        first_url = f"{base_url}?{urlencode({**common_params, 'page': '1'})}"
        if self.robots_allows(robots, first_url) is False:
            self.record_robots_block(source["source_id"], requested_date, first_url)
            return
        response, row = self.fetch(
            source_id=source["source_id"],
            requested_date=requested_date,
            request_role="wordpress_api",
            page_number=1,
            url=first_url,
            relative_path=Path(source["source_id"]) / requested_date / "api_page_001.json",
            headers={"Accept": "application/json"},
        )
        total_pages = 1
        if response is not None and response.status_code == 200:
            raw_total_pages = response.headers.get("X-WP-TotalPages", "1")
            try:
                total_pages = max(int(raw_total_pages), 1)
            except ValueError:
                total_pages = 1
        total_pages = min(total_pages, self.page_cap)
        for page_number in range(2, total_pages + 1):
            page_url = f"{base_url}?{urlencode({**common_params, 'page': str(page_number)})}"
            self.fetch(
                source_id=source["source_id"],
                requested_date=requested_date,
                request_role="wordpress_api",
                page_number=page_number,
                url=page_url,
                relative_path=Path(source["source_id"]) / requested_date / f"api_page_{page_number:03d}.json",
                headers={"Accept": "application/json"},
            )

        daily_url = format_url(source["daily_template"], requested_date)
        if self.robots_allows(robots, daily_url) is not False:
            self.fetch(
                source_id=source["source_id"],
                requested_date=requested_date,
                request_role="daily_html_reconciliation",
                page_number=1,
                url=daily_url,
                relative_path=Path(source["source_id"]) / requested_date / "daily_reconciliation.html",
            )
        else:
            self.record_robots_block(source["source_id"], requested_date, daily_url)

    def collect_diena(self, source: dict[str, Any], requested_date: str, robots: RobotFileParser | None) -> None:
        for role, template, filename in (
            ("monthly_index", source["month_template"], "month_index.html"),
            ("daily_archive", source["daily_template"], "daily_archive.html"),
        ):
            url = format_url(template, requested_date)
            if self.robots_allows(robots, url) is False:
                self.record_robots_block(source["source_id"], requested_date, url)
                continue
            self.fetch(
                source_id=source["source_id"],
                requested_date=requested_date,
                request_role=role,
                page_number=1,
                url=url,
                relative_path=Path(source["source_id"]) / requested_date / filename,
            )

    def _next_elpais_url(self, response: requests.Response) -> str | None:
        try:
            tree = html.fromstring(response.content)
        except (ValueError, html.ParserError):
            return None
        candidates = tree.xpath("//link[contains(concat(' ', normalize-space(@rel), ' '), ' next ')]/@href")
        if not candidates:
            candidates = tree.xpath("//a[contains(concat(' ', normalize-space(@rel), ' '), ' next ')]/@href")
        return urljoin(response.url, candidates[0]) if candidates else None

    def collect_elpais(self, source: dict[str, Any], requested_date: str, robots: RobotFileParser | None) -> None:
        current_url = format_url(source["daily_template"], requested_date)
        seen_urls: set[str] = set()
        for page_number in range(1, self.page_cap + 1):
            if current_url in seen_urls:
                break
            seen_urls.add(current_url)
            if self.robots_allows(robots, current_url) is False:
                self.record_robots_block(source["source_id"], requested_date, current_url)
                break
            response, _ = self.fetch(
                source_id=source["source_id"],
                requested_date=requested_date,
                request_role="daily_archive_page",
                page_number=page_number,
                url=current_url,
                relative_path=Path(source["source_id"]) / requested_date / f"archive_page_{page_number:03d}.html",
            )
            if response is None or response.status_code != 200:
                break
            next_url = self._next_elpais_url(response)
            if not next_url:
                break
            current_url = next_url

    def collect_mbl(self, source: dict[str, Any], requested_date: str, robots: RobotFileParser | None) -> None:
        url = format_url(source["daily_template"], requested_date)
        if self.robots_allows(robots, url) is False:
            self.record_robots_block(source["source_id"], requested_date, url)
            return
        self.fetch(
            source_id=source["source_id"],
            requested_date=requested_date,
            request_role="daily_archive_http",
            page_number=1,
            url=url,
            relative_path=Path(source["source_id"]) / requested_date / "daily_archive_http.html",
        )

    def collect_all(self) -> None:
        started = utc_now()
        for source in self.config["sources"]:
            robots = self.collect_preflight(source)
            for requested_date in self.config["fixed_dates"]:
                parser = source["parser"]
                if parser == "wordpress_api":
                    self.collect_wordpress(source, requested_date, robots)
                elif parser == "diena_html":
                    self.collect_diena(source, requested_date, robots)
                elif parser == "elpais_html":
                    self.collect_elpais(source, requested_date, robots)
                elif parser == "mbl_http_diagnostic":
                    self.collect_mbl(source, requested_date, robots)
                else:
                    raise ValueError(f"Unknown parser: {parser}")
        marker = {
            "schema_version": "1.0.0",
            "started_at_utc": started,
            "completed_at_utc": utc_now(),
            "run_date": self.config["run_date"],
            "fixed_dates": self.config["fixed_dates"],
            "source_ids": [source["source_id"] for source in self.config["sources"]],
            "request_rows": self.request_counter,
            "config_sha256": sha256_file(SCRIPT_DIR / "pilot_config.json"),
        }
        with self.complete_path.open("x", encoding="utf-8") as handle:
            json.dump(marker, handle, ensure_ascii=False, indent=2)
            handle.write("\n")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, default=SCRIPT_DIR / "pilot_config.json")
    parser.add_argument("--run-date", default=None, help="Must match config.run_date; prevents accidental scope drift.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    config = load_config(args.config.resolve())
    if args.run_date is not None and args.run_date != config["run_date"]:
        raise ValueError("--run-date must match the pre-specified run_date in pilot_config.json")
    raw_dir = REPO_ROOT / "data" / "raw" / "media_archive_pilot" / config["run_date"]
    collector = RawCollector(config, raw_dir)
    collector.collect_all()
    print(f"Raw collection complete: {raw_dir}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:  # fail closed and leave partial raw responses auditable
        print(f"COLLECTION FAILED: {type(exc).__name__}: {exc}", file=sys.stderr)
        raise
