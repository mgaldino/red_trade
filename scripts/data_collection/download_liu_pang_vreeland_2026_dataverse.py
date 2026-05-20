#!/usr/bin/env python3
"""Download Liu, Pang & Vreeland (2026) replication files from Harvard Dataverse.

Source DOI: https://doi.org/10.7910/DVN/MWAPWV
Dataverse API: https://dataverse.harvard.edu/api/datasets/:persistentId
Access: public API, no credentials required
Raw output: data/raw/external/liu_pang_vreeland_2026/files/
Documentation output: data/raw/external/liu_pang_vreeland_2026/
Last updated: 2026-05-19
"""

from __future__ import annotations

import csv
import hashlib
import json
import logging
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import date, datetime
from pathlib import Path
from typing import Any


DOI = "doi:10.7910/DVN/MWAPWV"
DOI_URL = "https://doi.org/10.7910/DVN/MWAPWV"
DATAVERSE_BASE = "https://dataverse.harvard.edu"
DATASET_API = f"{DATAVERSE_BASE}/api/datasets/:persistentId"
ACCESS_API = f"{DATAVERSE_BASE}/api/access/datafile"
REPO_ROOT = Path(__file__).resolve().parents[2]
RAW_ROOT = REPO_ROOT / "data" / "raw" / "external" / "liu_pang_vreeland_2026"
FILES_DIR = RAW_ROOT / "files"
USER_AGENT = (
    "red_trade_reproducible_collection/1.0 "
    "(academic replication; contact: repository owner)"
)


logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
LOGGER = logging.getLogger(__name__)


def request_bytes(url: str, *, timeout: int = 120, retries: int = 4) -> bytes:
    """Fetch bytes with exponential backoff."""
    headers = {"User-Agent": USER_AGENT}
    req = urllib.request.Request(url, headers=headers)
    last_error: Exception | None = None
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(req, timeout=timeout) as response:
                return response.read()
        except (urllib.error.URLError, TimeoutError) as exc:
            last_error = exc
            sleep_seconds = 2**attempt
            LOGGER.warning("Request failed (%s); retrying in %ss", exc, sleep_seconds)
            time.sleep(sleep_seconds)
    raise RuntimeError(f"Could not fetch {url}") from last_error


def request_json(url: str) -> dict[str, Any]:
    return json.loads(request_bytes(url).decode("utf-8"))


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def sanitize_filename(name: str) -> str:
    safe = re.sub(r"[^\w.\-+() ]+", "_", name, flags=re.UNICODE).strip()
    safe = re.sub(r"\s+", " ", safe)
    return safe or "dataverse_file"


def dataset_metadata() -> dict[str, Any]:
    query = urllib.parse.urlencode({"persistentId": DOI})
    url = f"{DATASET_API}?{query}"
    LOGGER.info("Fetching dataset metadata: %s", url)
    metadata = request_json(url)
    if metadata.get("status") != "OK":
        raise RuntimeError(f"Dataverse API returned non-OK status: {metadata}")
    return metadata


def extract_file_rows(metadata: dict[str, Any]) -> list[dict[str, Any]]:
    latest = metadata["data"]["latestVersion"]
    rows = []
    for item in latest.get("files", []):
        data_file = item["dataFile"]
        file_id = data_file["id"]
        original_name = data_file.get("filename", f"dataverse_file_{file_id}")
        storage_id = data_file.get("storageIdentifier", "")
        content_type = data_file.get("contentType", "")
        description = item.get("description", "")
        categories = "; ".join(item.get("categories", []))
        rows.append(
            {
                "file_id": file_id,
                "original_filename": original_name,
                "stored_filename": f"{file_id}_{sanitize_filename(original_name)}",
                "content_type": content_type,
                "storage_identifier": storage_id,
                "description": description,
                "categories": categories,
                "filesize": data_file.get("filesize", ""),
                "md5": data_file.get("md5", ""),
                "publication_date": data_file.get("publicationDate", ""),
                "download_url": f"{ACCESS_API}/{file_id}",
            }
        )
    rows.sort(key=lambda x: (str(x["original_filename"]).lower(), int(x["file_id"])))
    return rows


def write_manifest_csv(rows: list[dict[str, Any]]) -> None:
    path = RAW_ROOT / "file_manifest.csv"
    fieldnames = [
        "file_id",
        "original_filename",
        "stored_filename",
        "content_type",
        "filesize",
        "md5",
        "sha256",
        "publication_date",
        "categories",
        "description",
        "download_url",
        "relative_path",
    ]
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow({key: row.get(key, "") for key in fieldnames})


def yaml_quote(text: Any) -> str:
    value = "" if text is None else str(text)
    value = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{value}"'


def write_sources_yaml(metadata: dict[str, Any], rows: list[dict[str, Any]]) -> None:
    version = metadata["data"]["latestVersion"]
    citation = metadata["data"].get("citation", "")
    path = RAW_ROOT / "SOURCES.yaml"
    file_lines = []
    for row in rows:
        file_lines.extend(
            [
                "      - file_id: " + str(row["file_id"]),
                "        original_filename: " + yaml_quote(row["original_filename"]),
                "        stored_filename: " + yaml_quote(row["stored_filename"]),
                "        content_type: " + yaml_quote(row["content_type"]),
                "        sha256: " + yaml_quote(row.get("sha256", "")),
            ]
        )

    lines = [
        "sources:",
        "  - id: liu_pang_vreeland_2026_replication",
        '    name: "Replication Data for: China’s bilateral swap agreements and foreign policy"',
        '    provider: "Harvard Dataverse"',
        f"    url: {yaml_quote(DOI_URL)}",
        f"    api_docs: {yaml_quote(DATASET_API)}",
        "    access_method: api",
        "    requires_credentials: false",
        "    license: " + yaml_quote(version.get("license", "Dataverse dataset license not parsed")),
        "    citation: " + yaml_quote(citation),
        "    temporal_coverage: " + yaml_quote("To be determined from downloaded files"),
        "    geographic_coverage: " + yaml_quote("To be determined from downloaded files"),
        "    unit_of_analysis: " + yaml_quote("To be determined from downloaded files"),
        '    download_script: "scripts/data_collection/download_liu_pang_vreeland_2026_dataverse.py"',
        f"    date_accessed: {yaml_quote(date.today().isoformat())}",
        "    dataset_version:",
        "      version_number: " + yaml_quote(version.get("versionNumber", "")),
        "      version_minor_number: " + yaml_quote(version.get("versionMinorNumber", "")),
        "      version_state: " + yaml_quote(version.get("versionState", "")),
        "      release_time: " + yaml_quote(version.get("releaseTime", "")),
        "    files:",
        *file_lines,
    ]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_collection_log(metadata: dict[str, Any], rows: list[dict[str, Any]]) -> None:
    version = metadata["data"]["latestVersion"]
    total_bytes = sum(int(row["filesize"] or 0) for row in rows)
    data_files = [
        row for row in rows
        if Path(str(row["original_filename"])).suffix.lower()
        in {".csv", ".dta", ".rds", ".rda", ".rdata", ".xlsx", ".xls", ".tab", ".tsv", ".zip"}
    ]
    codebook_files = [
        row for row in rows
        if any(token in str(row["original_filename"]).lower()
               for token in ["readme", "codebook", "appendix", "do", "r", "stata"])
    ]
    lines = [
        "# Collection Log: Liu, Pang & Vreeland (2026)",
        "",
        f"Run timestamp: {datetime.now().strftime('%Y-%m-%d %H:%M:%S %Z')}",
        "",
        "## Source",
        "",
        f"- DOI: `{DOI_URL}`",
        f"- Dataverse persistent ID: `{DOI}`",
        f"- API endpoint: `{DATASET_API}`",
        f"- Dataset version: `{version.get('versionNumber', '')}.{version.get('versionMinorNumber', '')}`",
        f"- Version state: `{version.get('versionState', '')}`",
        f"- Release time: `{version.get('releaseTime', '')}`",
        "",
        "## Download Summary",
        "",
        f"- Files listed by Dataverse API: {len(rows)}",
        f"- Candidate data/archive files: {len(data_files)}",
        f"- Candidate documentation/code files: {len(codebook_files)}",
        f"- Total listed size: {total_bytes:,} bytes",
        f"- Raw files directory: `{FILES_DIR.relative_to(REPO_ROOT)}`",
        f"- Manifest: `{(RAW_ROOT / 'file_manifest.csv').relative_to(REPO_ROOT)}`",
        f"- Checksums: `{(RAW_ROOT / 'checksums.sha256').relative_to(REPO_ROOT)}`",
        "",
        "## Validation",
        "",
        "- The script verifies that each downloaded file exists and is non-empty.",
        "- SHA256 checksums are computed after download and recorded in `checksums.sha256` and `file_manifest.csv`.",
        "- Raw files are not modified after download.",
        "",
        "## Files",
        "",
    ]
    for row in rows:
        lines.append(
            "- `{}` -> `{}` ({} bytes, SHA256 `{}`)".format(
                row["original_filename"],
                row["relative_path"],
                row.get("downloaded_size", ""),
                row.get("sha256", ""),
            )
        )
    (RAW_ROOT / "COLLECTION_LOG.md").write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_checksums(rows: list[dict[str, Any]]) -> None:
    lines = [f"{row['sha256']}  {row['relative_path']}" for row in rows]
    (RAW_ROOT / "checksums.sha256").write_text("\n".join(lines) + "\n", encoding="utf-8")


def download_files(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    FILES_DIR.mkdir(parents=True, exist_ok=True)
    downloaded_rows = []
    for row in rows:
        output_path = FILES_DIR / row["stored_filename"]
        if not output_path.exists() or output_path.stat().st_size == 0:
            LOGGER.info("Downloading %s (%s)", row["original_filename"], row["file_id"])
            output_path.write_bytes(request_bytes(row["download_url"]))
        else:
            LOGGER.info("Keeping existing non-empty file: %s", output_path)

        if output_path.stat().st_size == 0:
            raise RuntimeError(f"Downloaded file is empty: {output_path}")

        row = dict(row)
        row["downloaded_size"] = output_path.stat().st_size
        row["sha256"] = sha256_file(output_path)
        row["relative_path"] = str(output_path.relative_to(REPO_ROOT))
        downloaded_rows.append(row)
    return downloaded_rows


def main() -> None:
    RAW_ROOT.mkdir(parents=True, exist_ok=True)
    metadata = dataset_metadata()
    (RAW_ROOT / "dataverse_dataset_metadata.json").write_text(
        json.dumps(metadata, indent=2, ensure_ascii=False),
        encoding="utf-8",
    )
    rows = extract_file_rows(metadata)
    if not rows:
        raise RuntimeError("No files were listed by the Dataverse API.")
    rows = download_files(rows)
    write_manifest_csv(rows)
    write_checksums(rows)
    write_sources_yaml(metadata, rows)
    write_collection_log(metadata, rows)
    LOGGER.info("Completed collection. Files downloaded: %s", len(rows))


if __name__ == "__main__":
    main()
