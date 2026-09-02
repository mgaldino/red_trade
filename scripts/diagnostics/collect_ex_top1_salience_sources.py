#!/usr/bin/env python3
"""Acquire raw HTTP evidence for the displaced-incumbent audit.

The source-evidence CSV is now an author-owned input. This collector validates
the frozen ledger/archive by default and, only with ``--acquire``, fetches raw
files that are absent. It never writes processed coding, comparisons, or
appendix tables.

Historical deterministic helper functions remain below for auditability during
the migration, but ``main()`` does not call them. Their logic is reproduced and
tested in ``targets``.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import logging
import re
import subprocess
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from datetime import date, datetime, timezone
from pathlib import Path
from typing import Iterable

import status_evidence_acquisition as acquisition


ROOT = Path(__file__).resolve().parents[2]
SAMPLE_CSV = (
    ROOT
    / "quality_reports"
    / "cross_country_sample"
    / "china_top_absorbing_cs_sample_fect_treated_countries.csv"
)
STATUS_COUNTRY_CSV = (
    ROOT
    / "data"
    / "processed"
    / "status_cue_salience"
    / "status_cue_country_codes.csv"
)
INCUMBENT_PATTERN = "incumbent_salience_moderators_*.csv"
INCUMBENT_DIR = ROOT / "data" / "processed" / "diagnostics"

RAW_DIR = ROOT / "data" / "raw" / "ex_top1_salience"
PROCESSED_DIR = ROOT / "data" / "processed" / "ex_top1_salience"
REPORT_DIR = ROOT / "quality_reports" / "ex_top1_salience"

EVIDENCE_CSV = PROCESSED_DIR / "ex_top1_source_evidence.csv"
SOURCES_YAML = PROCESSED_DIR / "SOURCES.yaml"
DATA_DICTIONARY = PROCESSED_DIR / "DATA_DICTIONARY.md"
COLLECTION_LOG = REPORT_DIR / "collection_log.md"
SEARCH_PLAN_CSV = PROCESSED_DIR / "ex_top1_search_plan.csv"
CHECKSUMS = RAW_DIR / "checksums.sha256"
EXPECTED_MANIFEST_ENTRIES = 48

ACCESSED_AT = datetime.now(timezone.utc).replace(microsecond=0).isoformat()
ACCESS_DATE = str(date.today())
HTTP_TIMEOUT_SECONDS = 8
USER_AGENT = (
    "RDD-Trade ex-Top1 salience collector/1.0 "
    "(academic reproducibility; contact: local project maintainer)"
)

EVIDENCE_COLUMNS = [
    "source_id",
    "iso3c",
    "country_name",
    "entry_year",
    "incumbent_partner_name",
    "incumbent_partner_iso3",
    "incumbent_rank_year",
    "incumbent_rank_source_file",
    "incumbent_export_share",
    "china_export_share",
    "evidence_year",
    "source_type",
    "source_name",
    "source_country",
    "eligible_source",
    "language",
    "title",
    "publication_date",
    "url",
    "archive_url",
    "raw_file",
    "query_used",
    "accessed_at",
    "coverage_topic",
    "rank_label_original",
    "rank_label_english",
    "label_type",
    "explicit_rank_language",
    "mentions_incumbent_trade",
    "mentions_china",
    "mentions_rank_change_or_displacement",
    "incumbent_partner_named",
    "excerpt_under_25_words",
    "evidence_strength",
    "count_for_benchmark",
    "notes",
]

SEARCH_COLUMNS = [
    "iso3c",
    "country_name",
    "entry_year",
    "incumbent_partner_name",
    "incumbent_partner_iso3",
    "window_start_year",
    "window_end_year",
    "query_used",
    "language_scope",
    "source_strategy",
    "accessed_at",
    "notes",
]


@dataclass(frozen=True)
class EvidenceSeed:
    source_id: str
    iso3c: str
    evidence_year: int
    source_type: str
    source_name: str
    source_country: str
    eligible_source: bool
    language: str
    title: str
    publication_date: str
    url: str
    query_used: str
    coverage_topic: str
    rank_label_original: str
    rank_label_english: str
    label_type: str
    explicit_rank_language: bool
    mentions_incumbent_trade: bool
    mentions_china: bool
    mentions_rank_change_or_displacement: bool
    incumbent_partner_named: str
    excerpt_under_25_words: str
    evidence_strength: str
    count_for_benchmark: bool
    notes: str = ""
    archive_url: str = ""
    fetch_url: str = ""


@dataclass
class FetchResult:
    raw_file: str = ""
    status: str = "not_attempted"
    status_code: int | None = None
    content_type: str = ""
    error: str = ""
    size_bytes: int = 0


def slugify(value: str, max_len: int = 80) -> str:
    value = value.lower()
    value = re.sub(r"[^a-z0-9]+", "_", value)
    value = re.sub(r"_+", "_", value).strip("_")
    return value[:max_len].strip("_") or "source"


def rel(path: Path) -> str:
    return str(path.relative_to(ROOT))


def ensure_dirs() -> None:
    for path in [RAW_DIR, PROCESSED_DIR, REPORT_DIR, RAW_DIR / "search_logs"]:
        path.mkdir(parents=True, exist_ok=True)


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as f:
        return list(csv.DictReader(f))


def write_csv(path: Path, rows: Iterable[dict[str, str]], columns: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=columns, extrasaction="ignore")
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")


def latest_incumbent_csv() -> Path:
    candidates = sorted(INCUMBENT_DIR.glob(INCUMBENT_PATTERN))
    if not candidates:
        raise FileNotFoundError(f"No incumbent diagnostic found in {INCUMBENT_DIR}")
    return candidates[-1]


def read_primary_sample() -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for row in read_csv(SAMPLE_CSV):
        if row.get("model") == "No covariates":
            rows.append(
                {
                    "iso3c": row["iso3c"],
                    "country_name": row["country_name"],
                    "entry_year": str(int(row["first_treated_year"])),
                }
            )
    if not rows:
        raise RuntimeError(f"No 'No covariates' rows found in {SAMPLE_CSV}")
    return rows


def read_incumbents(sample: list[dict[str, str]], incumbent_csv: Path) -> dict[str, dict[str, str]]:
    sample_iso = {row["iso3c"] for row in sample}
    incumbents: dict[str, dict[str, str]] = {}
    for row in read_csv(incumbent_csv):
        iso3c = row.get("iso3c", "")
        if iso3c in sample_iso:
            incumbents[iso3c] = {
                "incumbent_partner_iso3": row.get("displaced_partner", ""),
                "incumbent_partner_name": row.get("displaced_partner_name", ""),
                "incumbent_rank_year": str(int(float(row.get("t0", "0"))) - 1)
                if row.get("t0")
                else "",
                "incumbent_rank_source_file": rel(incumbent_csv),
                "incumbent_export_share": row.get("displaced_export_share_t0_minus_1", ""),
                "china_export_share": row.get("china_export_share_t0_minus_1", ""),
                "incumbent_notes": row.get("displacement_salience_warning", ""),
            }
    missing = sorted(sample_iso - set(incumbents))
    if missing:
        raise RuntimeError(f"Missing incumbent rows for: {', '.join(missing)}")
    return incumbents


def request_url(url: str, path: Path) -> FetchResult:
    path.parent.mkdir(parents=True, exist_ok=True)
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    last_error = ""
    error_path = path.with_suffix(path.suffix + ".error.txt")
    for attempt in range(2):
        try:
            with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT_SECONDS) as response:
                body = response.read()
                path.write_bytes(body)
                if error_path.exists():
                    error_path.unlink()
                return FetchResult(
                    raw_file=rel(path),
                    status="ok",
                    status_code=getattr(response, "status", None),
                    content_type=response.headers.get("Content-Type", ""),
                    size_bytes=len(body),
                )
        except urllib.error.HTTPError as err:
            body = err.read()
            if body:
                path.write_bytes(body)
            return FetchResult(
                raw_file=rel(path) if path.exists() else "",
                status="http_error",
                status_code=err.code,
                content_type=err.headers.get("Content-Type", ""),
                error=str(err),
                size_bytes=path.stat().st_size if path.exists() else 0,
            )
        except Exception as err:  # noqa: BLE001 - exact exception is audit metadata
            last_error = repr(err)
            time.sleep(1.5 * (attempt + 1))
    curl_result = request_url_with_curl(url, path, last_error)
    if curl_result.status in {"ok", "http_error"}:
        if curl_result.status == "ok" and error_path.exists():
            error_path.unlink()
        return curl_result
    if path.exists() and path.is_file() and path.stat().st_size > 0:
        return FetchResult(
            raw_file=rel(path),
            status="cached_ok",
            error=last_error,
            size_bytes=path.stat().st_size,
        )
    error_path.write_text(last_error, encoding="utf-8")
    return FetchResult(raw_file=rel(error_path), status="error", error=last_error)


def request_url_with_curl(url: str, path: Path, prior_error: str) -> FetchResult:
    trailer = "\n%{http_code}\n%{content_type}\n%{size_download}"
    cmd = [
        "curl",
        "-L",
        "-sS",
        "--max-time",
        str(max(HTTP_TIMEOUT_SECONDS * 2, 15)),
        "-A",
        USER_AGENT,
        "-o",
        str(path),
        "-w",
        trailer,
        url,
    ]
    try:
        completed = subprocess.run(
            cmd,
            check=False,
            capture_output=True,
            text=True,
            timeout=max(HTTP_TIMEOUT_SECONDS * 3, 30),
        )
    except Exception as err:  # noqa: BLE001 - exact exception is audit metadata
        return FetchResult(status="error", error=f"{prior_error}; curl fallback: {err!r}")

    parts = completed.stdout.strip().split("\n")
    status_code = None
    content_type = ""
    size_bytes = path.stat().st_size if path.exists() else 0
    if len(parts) >= 3:
        try:
            status_code = int(parts[-3])
        except ValueError:
            status_code = None
        content_type = parts[-2]
        try:
            size_bytes = int(float(parts[-1]))
        except ValueError:
            pass

    if completed.returncode == 0 and path.exists() and path.stat().st_size > 0:
        status = "ok" if status_code is not None and status_code < 400 else "http_error"
        return FetchResult(
            raw_file=rel(path),
            status=status,
            status_code=status_code,
            content_type=content_type,
            error=prior_error,
            size_bytes=size_bytes,
        )
    if path.exists() and path.stat().st_size > 0:
        return FetchResult(
            raw_file=rel(path),
            status="http_error",
            status_code=status_code,
            content_type=content_type,
            error=f"{prior_error}; curl stderr: {completed.stderr.strip()}",
            size_bytes=path.stat().st_size,
        )
    return FetchResult(
        status="error",
        status_code=status_code,
        content_type=content_type,
        error=f"{prior_error}; curl stderr: {completed.stderr.strip()}",
    )


def extension_for_url(url: str, content_type: str = "") -> str:
    suffix = Path(urllib.parse.urlparse(url).path).suffix.lower()
    if suffix in {".html", ".htm", ".pdf", ".json", ".txt", ".xml"}:
        return suffix
    ctype = content_type.lower()
    if "pdf" in ctype:
        return ".pdf"
    if "json" in ctype:
        return ".json"
    if "xml" in ctype:
        return ".xml"
    return ".html"


def fetch_evidence(
    seed: EvidenceSeed,
    sample_lookup: dict[str, dict[str, str]],
    incumbents: dict[str, dict[str, str]],
) -> tuple[dict[str, str], dict[str, object]]:
    country = sample_lookup[seed.iso3c]
    incumbent = incumbents[seed.iso3c]
    country_dir = RAW_DIR / seed.iso3c / str(seed.evidence_year) / slugify(seed.source_name)
    planned_path = country_dir / f"{slugify(seed.source_id)}.html"
    download_url = seed.fetch_url or seed.url
    result = request_url(download_url, planned_path)
    if result.raw_file and result.status in {"ok", "cached_ok", "http_error"}:
        raw_path = ROOT / result.raw_file
        suffix = extension_for_url(seed.url, result.content_type)
        if raw_path.suffix.lower() != suffix and raw_path.exists():
            target = raw_path.with_suffix(suffix)
            try:
                raw_path.rename(target)
                result.raw_file = rel(target)
            except OSError:
                pass

    notes = seed.notes
    evidence_strength = seed.evidence_strength
    count_for_benchmark = seed.count_for_benchmark
    if not seed.eligible_source:
        count_for_benchmark = False
        if "INELIGIBLE_SOURCE" not in notes:
            notes = f"INELIGIBLE_SOURCE: {notes}".strip()
    if not seed.count_for_benchmark:
        count_for_benchmark = False
        if "DO_NOT_COUNT" not in notes:
            notes = f"DO_NOT_COUNT: {notes or 'supplemental audit context only.'}".strip()
    if result.status not in {"ok", "cached_ok"}:
        count_for_benchmark = False
        evidence_strength = "weak"
        prefix = f"DO_NOT_COUNT: raw fetch status is {result.status}"
        if result.status_code is not None:
            prefix += f" ({result.status_code})"
        notes = f"{prefix}. {notes}".strip()

    row = {
        "source_id": seed.source_id,
        "iso3c": seed.iso3c,
        "country_name": country["country_name"],
        "entry_year": country["entry_year"],
        **incumbent,
        "evidence_year": str(seed.evidence_year),
        "source_type": seed.source_type,
        "source_name": seed.source_name,
        "source_country": seed.source_country,
        "eligible_source": str(seed.eligible_source).lower(),
        "language": seed.language,
        "title": seed.title,
        "publication_date": seed.publication_date,
        "url": seed.url,
        "archive_url": seed.archive_url,
        "raw_file": result.raw_file,
        "query_used": seed.query_used,
        "accessed_at": ACCESSED_AT,
        "coverage_topic": seed.coverage_topic,
        "rank_label_original": seed.rank_label_original,
        "rank_label_english": seed.rank_label_english,
        "label_type": seed.label_type,
        "explicit_rank_language": str(seed.explicit_rank_language).lower(),
        "mentions_incumbent_trade": str(seed.mentions_incumbent_trade).lower(),
        "mentions_china": str(seed.mentions_china).lower(),
        "mentions_rank_change_or_displacement": str(seed.mentions_rank_change_or_displacement).lower(),
        "incumbent_partner_named": seed.incumbent_partner_named,
        "excerpt_under_25_words": seed.excerpt_under_25_words,
        "evidence_strength": evidence_strength,
        "count_for_benchmark": str(count_for_benchmark).lower(),
        "notes": notes,
    }
    meta = {
        "source_id": seed.source_id,
        "iso3c": seed.iso3c,
        "url": seed.url,
        "fetch_url": download_url,
        "fetch_status": result.status,
        "status_code": result.status_code,
        "content_type": result.content_type,
        "raw_file": result.raw_file,
        "size_bytes": result.size_bytes,
        "error": result.error,
        "accessed_at": ACCESSED_AT,
        "eligible_source": seed.eligible_source,
        "count_for_benchmark_after_fetch": count_for_benchmark,
    }
    write_json(country_dir / f"{slugify(seed.source_id)}.metadata.json", meta)
    return row, meta


def search_queries(sample: list[dict[str, str]], incumbents: dict[str, dict[str, str]]) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    for country in sample:
        inc = incumbents[country["iso3c"]]
        window_start = int(country["entry_year"]) - 1
        window_end = int(country["entry_year"]) + 1
        country_name = country["country_name"]
        partner = inc["incumbent_partner_name"]
        base_queries = [
            f'"{country_name}" "{partner}" "largest export market" {window_start} {window_end}',
            f'"{country_name}" "{partner}" "top export destination" {window_start} {window_end}',
            f'"{country_name}" "{partner}" trade exports {window_start} {window_end}',
            f'"China" "{country_name}" "{partner}" overtook displaced replaced {window_start} {window_end}',
        ]
        for query in base_queries:
            rows.append(
                {
                    "iso3c": country["iso3c"],
                    "country_name": country_name,
                    "entry_year": country["entry_year"],
                    "incumbent_partner_name": partner,
                    "incumbent_partner_iso3": inc["incumbent_partner_iso3"],
                    "window_start_year": str(window_start),
                    "window_end_year": str(window_end),
                    "query_used": query,
                    "language_scope": "English plus local-language variants where relevant",
                    "source_strategy": "local newspaper, national news agency, official statistics/trade ministry, and supplemental archived/international context",
                    "accessed_at": ACCESSED_AT,
                    "notes": "Search terms logged for reproducibility; raw files are preserved for located URLs.",
                }
            )
    return rows


def seeds() -> list[EvidenceSeed]:
    return [
        EvidenceSeed(
            source_id="phl_psa_december_2004_exports_japan",
            iso3c="PHL",
            evidence_year=2005,
            source_type="official_statistics",
            source_name="Philippine Statistics Authority",
            source_country="Philippines",
            eligible_source=True,
            language="en",
            title="Merchandise Export Performance: December 2004",
            publication_date="2005-02-10",
            url="https://psa.gov.ph/statistics/export-import/monthly/node/6917",
            query_used='"Japan" "country\'s top export market" "Philippines" "2004"',
            coverage_topic="Japan as top 2004 export market before China-entry year",
            rank_label_original="Japan got the biggest share of exports",
            rank_label_english="Japan had the biggest share of exports",
            label_type="incumbent_export_rank",
            explicit_rank_language=True,
            mentions_incumbent_trade=True,
            mentions_china=True,
            mentions_rank_change_or_displacement=False,
            incumbent_partner_named="Japan",
            excerpt_under_25_words="Japan got the biggest share of exports at 20.1 percent for the year 2004.",
            evidence_strength="strong",
            count_for_benchmark=True,
            notes="Official local statistics source; useful despite later 2005 annual rank inconsistency.",
        ),
        EvidenceSeed(
            source_id="chl_aqua_china_displaces_us_2008_01_23",
            iso3c="CHL",
            evidence_year=2008,
            source_type="business_news",
            source_name="AQUA",
            source_country="Chile",
            eligible_source=True,
            language="es",
            title="China desplaza a Estados Unidos como principal socio comercial de Chile",
            publication_date="2008-01-23",
            url="https://www.aqua.cl/china-desplaza-a-estados-unidos-como-principal-socio-comercial-de-chile/",
            query_used='"China desplazó a Estados Unidos" "exportaciones chilenas"',
            coverage_topic="China displacement of United States as export destination",
            rank_label_original="principal destino (por país) de las exportaciones chilenas",
            rank_label_english="main destination by country for Chilean exports",
            label_type="displacement",
            explicit_rank_language=True,
            mentions_incumbent_trade=True,
            mentions_china=True,
            mentions_rank_change_or_displacement=True,
            incumbent_partner_named="United States",
            excerpt_under_25_words="China desplazó a Estados Unidos como el principal destino.",
            evidence_strength="strong",
            count_for_benchmark=True,
        ),
        EvidenceSeed(
            source_id="chl_diario_financiero_2009_01_12",
            iso3c="CHL",
            evidence_year=2009,
            source_type="business_news",
            source_name="Diario Financiero",
            source_country="Chile",
            eligible_source=True,
            language="es",
            title="Exportaciones chilenas crecieron sólo 4% en 2008",
            publication_date="2009-01-12",
            url="https://www.df.cl/economia-y-politica/exportaciones-chilenas-crecieron-solo-4-en-2008",
            query_used='"China sigue siendo" "principal destino" "exportaciones chilenas" 2008 Estados Unidos',
            coverage_topic="China-US export-rank comparison after incumbent displacement",
            rank_label_original="principal destino de los embarques chilenos en el mundo",
            rank_label_english="main destination for Chilean shipments worldwide",
            label_type="displacement",
            explicit_rank_language=True,
            mentions_incumbent_trade=True,
            mentions_china=True,
            mentions_rank_change_or_displacement=True,
            incumbent_partner_named="United States",
            excerpt_under_25_words="China sigue siendo el principal destino de las exportaciones chilenas.",
            evidence_strength="strong",
            count_for_benchmark=True,
        ),
        EvidenceSeed(
            source_id="bra_agencia_brasil_2009_05_04",
            iso3c="BRA",
            evidence_year=2009,
            source_type="national_news_agency",
            source_name="Agência Brasil",
            source_country="Brazil",
            eligible_source=True,
            language="pt",
            title="China supera Estados Unidos e torna-se maior parceiro comercial do Brasil",
            publication_date="2009-05-04",
            url="https://memoria.ebc.com.br/agenciabrasil/noticia/2009-05-04/china-supera-estados-unidos-e-torna-se-maior-parceiro-comercial-do-brasil",
            query_used='"China supera Estados Unidos" "maior parceiro comercial do Brasil" 2009 Agência Brasil',
            coverage_topic="China displacement of United States as Brazil trade partner",
            rank_label_original="maior parceiro comercial do país",
            rank_label_english="largest trading partner",
            label_type="displacement",
            explicit_rank_language=True,
            mentions_incumbent_trade=True,
            mentions_china=True,
            mentions_rank_change_or_displacement=True,
            incumbent_partner_named="United States",
            excerpt_under_25_words="Pela primeira vez, a China se consolidou como maior parceiro comercial do país.",
            evidence_strength="strong",
            count_for_benchmark=True,
        ),
        EvidenceSeed(
            source_id="bra_mre_resenha_lula_2009_05_19",
            iso3c="BRA",
            evidence_year=2009,
            source_type="official_speech",
            source_name="Ministério das Relações Exteriores / FUNAG",
            source_country="Brazil",
            eligible_source=True,
            language="pt",
            title="Resenha de Política Exterior do Brasil, número 104, 1º semestre de 2009",
            publication_date="2009-05-19",
            url="https://www.funag.gov.br/chdd/images/Resenhas/Novas/Resenha_numero_104_1_2009.pdf",
            query_used='site:funag.gov.br 2009 Lula China principal parceiro comercial Brasil Beijing "maior parceiro"',
            coverage_topic="Official Brazil-China rank language after US displacement",
            rank_label_original="maior parceiro comercial brasileiro",
            rank_label_english="largest Brazilian trading partner",
            label_type="displacement",
            explicit_rank_language=True,
            mentions_incumbent_trade=True,
            mentions_china=True,
            mentions_rank_change_or_displacement=True,
            incumbent_partner_named="United States",
            excerpt_under_25_words="A China passou a ser, em 2009, o maior parceiro comercial brasileiro.",
            evidence_strength="strong",
            count_for_benchmark=True,
        ),
        EvidenceSeed(
            source_id="mys_miti_report_2009_singapore_largest_export_market",
            iso3c="MYS",
            evidence_year=2010,
            source_type="official_report",
            source_name="Ministry of Investment, Trade and Industry",
            source_country="Malaysia",
            eligible_source=True,
            language="en",
            title="Malaysia International Trade and Industry Report 2009",
            publication_date="2010-01-01",
            url="https://www.miti.gov.my/miti/resources/auto%2520download%2520images/55555e1816f94.pdf",
            query_used='"Singapore with RM77.2 billion" "largest market in 2009" Malaysia exports',
            coverage_topic="Singapore as largest export market in 2009",
            rank_label_original="Singapore ... was the largest market in 2009 for Malaysia's exports",
            rank_label_english="Singapore was the largest market for Malaysia's exports",
            label_type="incumbent_export_rank",
            explicit_rank_language=True,
            mentions_incumbent_trade=True,
            mentions_china=True,
            mentions_rank_change_or_displacement=False,
            incumbent_partner_named="Singapore",
            excerpt_under_25_words="Singapore with RM77.2 billion was the largest market in 2009.",
            evidence_strength="strong",
            count_for_benchmark=True,
            notes="Official report also notes China/Hong Kong aggregation can alter the rank interpretation.",
        ),
        EvidenceSeed(
            source_id="mys_miti_bernama_china_second_2010_01_07",
            iso3c="MYS",
            evidence_year=2010,
            source_type="government_news",
            source_name="MITI / Bernama",
            source_country="Malaysia",
            eligible_source=True,
            language="en",
            title="Malaysia's Total Trade With China Exceeds US$28.4 Billion In 2009",
            publication_date="2010-01-07",
            url="https://www.miti.gov.my/index.php/pages/view/1446",
            query_used='Malaysia China largest trading partner 2009 2010 official Bernama "largest trading partner"',
            coverage_topic="Contemporaneous China non-top rank in Malaysia trade coverage",
            rank_label_original="second largest trading partner; second largest export market",
            rank_label_english="second-largest trading partner and export market",
            label_type="non_top_rank",
            explicit_rank_language=True,
            mentions_incumbent_trade=False,
            mentions_china=True,
            mentions_rank_change_or_displacement=False,
            incumbent_partner_named="",
            excerpt_under_25_words="China is now Malaysia's second largest trading partner.",
            evidence_strength="moderate",
            count_for_benchmark=False,
            notes="DO_NOT_COUNT: useful for rank-definition audit but does not name Singapore.",
        ),
        EvidenceSeed(
            source_id="aus_dfat_composition_trade_2008",
            iso3c="AUS",
            evidence_year=2009,
            source_type="government_news",
            source_name="Australian Department of Foreign Affairs and Trade",
            source_country="Australia",
            eligible_source=True,
            language="en",
            title="Australia's Composition of Trade 2008",
            publication_date="2009-06-17",
            url="https://www.dfat.gov.au/news/media/Pages/australia-s-composition-of-trade-2008",
            query_used='"Japan remained Australia\'s largest export market" 2008 DFAT',
            coverage_topic="Japan as incumbent largest export market before China entry",
            rank_label_original="Japan remained Australia's largest export market",
            rank_label_english="Japan remained Australia's largest export market",
            label_type="incumbent_export_rank",
            explicit_rank_language=True,
            mentions_incumbent_trade=True,
            mentions_china=True,
            mentions_rank_change_or_displacement=False,
            incumbent_partner_named="Japan",
            excerpt_under_25_words="Japan remained Australia's largest export market.",
            evidence_strength="strong",
            count_for_benchmark=True,
            archive_url="https://r.jina.ai/http://r.jina.ai/http://https://www.dfat.gov.au/news/media/Pages/australia-s-composition-of-trade-2008",
            fetch_url="https://r.jina.ai/http://r.jina.ai/http://https://www.dfat.gov.au/news/media/Pages/australia-s-composition-of-trade-2008",
            notes="Fetched via r.jina.ai Markdown fallback because direct DFAT requests time out from this environment.",
        ),
        EvidenceSeed(
            source_id="aus_dfat_composition_trade_2008_09",
            iso3c="AUS",
            evidence_year=2009,
            source_type="government_news",
            source_name="Australian Department of Foreign Affairs and Trade",
            source_country="Australia",
            eligible_source=True,
            language="en",
            title="Australia's Composition of Trade 2008-09",
            publication_date="2009-11-30",
            url="https://www.dfat.gov.au/news/media/Pages/australia-s-composition-of-trade-2008-09",
            query_used='"Japan was Australia\'s largest export market in 2008-09" DFAT',
            coverage_topic="Japan as incumbent largest export market in fiscal 2008-09",
            rank_label_original="Japan was Australia's largest export market",
            rank_label_english="Japan was Australia's largest export market",
            label_type="incumbent_export_rank",
            explicit_rank_language=True,
            mentions_incumbent_trade=True,
            mentions_china=True,
            mentions_rank_change_or_displacement=False,
            incumbent_partner_named="Japan",
            excerpt_under_25_words="Japan was Australia's largest export market in 2008-09.",
            evidence_strength="strong",
            count_for_benchmark=True,
            archive_url="https://r.jina.ai/http://r.jina.ai/http://https://www.dfat.gov.au/news/media/Pages/australia-s-composition-of-trade-2008-09",
            fetch_url="https://r.jina.ai/http://r.jina.ai/http://https://www.dfat.gov.au/news/media/Pages/australia-s-composition-of-trade-2008-09",
            notes="Fetched via r.jina.ai Markdown fallback because direct DFAT requests time out from this environment.",
        ),
        EvidenceSeed(
            source_id="aus_dfat_china_became_largest_export_market_2010",
            iso3c="AUS",
            evidence_year=2010,
            source_type="government_news",
            source_name="Australian Department of Foreign Affairs and Trade",
            source_country="Australia",
            eligible_source=True,
            language="en",
            title="Australian trade volumes grow despite financial crisis",
            publication_date="2010-06-04",
            url="https://www.dfat.gov.au/news/media/Pages/australian-trade-volumes-grow-despite-financial-crisis",
            query_used='"China became Australia\'s largest export market" "Japan was Australia\'s second largest export market"',
            coverage_topic="China displacement and Japan second-largest status",
            rank_label_original="China became Australia's largest export market; Japan was second",
            rank_label_english="China became largest and Japan became second-largest export market",
            label_type="displacement",
            explicit_rank_language=True,
            mentions_incumbent_trade=True,
            mentions_china=True,
            mentions_rank_change_or_displacement=True,
            incumbent_partner_named="Japan",
            excerpt_under_25_words="China became Australia's largest export market in 2009.",
            evidence_strength="strong",
            count_for_benchmark=True,
            archive_url="https://r.jina.ai/http://r.jina.ai/http://https://www.dfat.gov.au/news/media/Pages/australian-trade-volumes-grow-despite-financial-crisis",
            fetch_url="https://r.jina.ai/http://r.jina.ai/http://https://www.dfat.gov.au/news/media/Pages/australian-trade-volumes-grow-despite-financial-crisis",
            notes="Fetched via r.jina.ai Markdown fallback because direct DFAT requests time out from this environment.",
        ),
        EvidenceSeed(
            source_id="aus_afr_china_trading_partner_2009",
            iso3c="AUS",
            evidence_year=2009,
            source_type="business_news",
            source_name="Australian Financial Review",
            source_country="Australia",
            eligible_source=True,
            language="en",
            title="China hits the spot as trading partner",
            publication_date="2009-11-09",
            url="https://www.afr.com/markets/china-hits-the-spot-as-trading-partner-20091109-iwhtx",
            query_used='"China hits the spot as trading partner" "Australia" "China" "largest trading partner"',
            coverage_topic="China as Australia's largest aggregate trading partner before export-market entry",
            rank_label_original="Australia's largest trading partner",
            rank_label_english="Australia's largest aggregate trading partner",
            label_type="broad_trade_partner_rank",
            explicit_rank_language=True,
            mentions_incumbent_trade=True,
            mentions_china=True,
            mentions_rank_change_or_displacement=True,
            incumbent_partner_named="Japan",
            excerpt_under_25_words="China has taken its position as Australia's largest trading partner.",
            evidence_strength="moderate",
            count_for_benchmark=False,
            notes=(
                "DO_NOT_COUNT: broad trade-partner metric combines exports and imports, "
                "goods and services; not evidence of export-destination status. Retained "
                "as metric-mismatch and salience context."
            ),
        ),
        EvidenceSeed(
            source_id="ury_presidencia_2012_exports_brazil",
            iso3c="URY",
            evidence_year=2012,
            source_type="government_news",
            source_name="Presidencia Uruguay",
            source_country="Uruguay",
            eligible_source=True,
            language="es",
            title="En 2011 las exportaciones uruguayas al mundo totalizaron U$S 8 mil millones",
            publication_date="2012-01-02",
            url="https://www.gub.uy/presidencia/comunicacion/noticias/2011-exportaciones-uruguayas-mundo-totalizaron-us-8-mil-millones",
            query_used='"Brasil" "principal destino" "exportaciones uruguayas" 2011 Presidencia',
            coverage_topic="Brazil as main export destination before Uruguay China entry",
            rank_label_original="Brasil es el principal destino de las ventas al exterior",
            rank_label_english="Brazil is the main destination for foreign sales",
            label_type="incumbent_export_rank",
            explicit_rank_language=True,
            mentions_incumbent_trade=True,
            mentions_china=True,
            mentions_rank_change_or_displacement=False,
            incumbent_partner_named="Brazil",
            excerpt_under_25_words="Brasil es el principal destino de las ventas al exterior.",
            evidence_strength="strong",
            count_for_benchmark=True,
        ),
        EvidenceSeed(
            source_id="ury_montevideo_2013_01_02_brazil",
            iso3c="URY",
            evidence_year=2013,
            source_type="local_news",
            source_name="Montevideo Portal",
            source_country="Uruguay",
            eligible_source=True,
            language="es",
            title="Uruguay cerró 2012 con superávit comercial de USD 215 M tras déficit en 2011",
            publication_date="2013-01-02",
            url="https://www.montevideo.com.uy/Noticias/Uruguay-cerro-2012-con-superavit-comercial-de-USD-215-M-tras-deficit-en-2011-uc188704",
            query_used='"Brasil se mantiene como el principal destino" "Uruguay" "2012"',
            coverage_topic="Brazil as principal export destination in 2012",
            rank_label_original="Brasil se mantiene como el principal destino",
            rank_label_english="Brazil remains the main destination",
            label_type="incumbent_export_rank",
            explicit_rank_language=True,
            mentions_incumbent_trade=True,
            mentions_china=True,
            mentions_rank_change_or_displacement=False,
            incumbent_partner_named="Brazil",
            excerpt_under_25_words="Brasil se mantiene como el principal destino.",
            evidence_strength="strong",
            count_for_benchmark=True,
        ),
        EvidenceSeed(
            source_id="kwt_kuna_ambassador_kotra_2018",
            iso3c="KWT",
            evidence_year=2018,
            source_type="national_news_agency",
            source_name="Kuwait News Agency",
            source_country="Kuwait",
            eligible_source=True,
            language="en",
            title="Kuwait Amb. to S. Korea discusses cooperation during Seoul meeting",
            publication_date="2018-09-10",
            url="https://www.kuna.net.kw/ArticleDetails.aspx?Language=en&id=2745641",
            query_used='site:kuna.net.kw Kuwait South Korea trade 2018 2017 USD 11 billion',
            coverage_topic="Kuwait-South Korea trade coverage without export-rank label",
            rank_label_original="",
            rank_label_english="",
            label_type="trade_coverage",
            explicit_rank_language=False,
            mentions_incumbent_trade=True,
            mentions_china=False,
            mentions_rank_change_or_displacement=False,
            incumbent_partner_named="South Korea",
            excerpt_under_25_words="Commercial exchange between the two countries in 2017 reached about USD 11 billion.",
            evidence_strength="moderate",
            count_for_benchmark=True,
        ),
        EvidenceSeed(
            source_id="kwt_kuna_trade_volume_2018_2019",
            iso3c="KWT",
            evidence_year=2019,
            source_type="national_news_agency",
            source_name="Kuwait News Agency",
            source_country="Kuwait",
            eligible_source=True,
            language="en",
            title="Kuwait, South Korea trade volume totals USD 14 billion in 2018",
            publication_date="2019-04-27",
            url="https://www.kuna.net.kw/ArticleDetails.aspx?id=2791488&language=en",
            query_used='site:kuna.net.kw "Kuwait, South Korea trade volume totals USD 14 billion in 2018"',
            coverage_topic="Kuwaiti exports to South Korea, no Kuwait export-destination rank",
            rank_label_original="",
            rank_label_english="",
            label_type="trade_coverage",
            explicit_rank_language=False,
            mentions_incumbent_trade=True,
            mentions_china=False,
            mentions_rank_change_or_displacement=False,
            incumbent_partner_named="South Korea",
            excerpt_under_25_words="Kuwaiti exports ... totaled USD 12.7 billion.",
            evidence_strength="moderate",
            count_for_benchmark=True,
        ),
        EvidenceSeed(
            source_id="kwt_kuna_korea_forum_2019",
            iso3c="KWT",
            evidence_year=2019,
            source_type="national_news_agency",
            source_name="Kuwait News Agency",
            source_country="Kuwait",
            eligible_source=True,
            language="en",
            title="S. Korean PM affirms deep-rooted ties with Kuwait",
            publication_date="2019-05-02",
            url="https://www.kuna.net.kw/ArticleDetails.aspx?Language=en&id=2794430",
            query_used='site:kuna.net.kw "Trade volume between Kuwait and South Korea reached USD 14 billion in 2018"',
            coverage_topic="Second KUNA trade coverage for South Korea",
            rank_label_original="",
            rank_label_english="",
            label_type="trade_coverage",
            explicit_rank_language=False,
            mentions_incumbent_trade=True,
            mentions_china=False,
            mentions_rank_change_or_displacement=False,
            incumbent_partner_named="South Korea",
            excerpt_under_25_words="Trade volume between Kuwait and South Korea reached USD 14 billion.",
            evidence_strength="moderate",
            count_for_benchmark=True,
        ),
        EvidenceSeed(
            source_id="qat_peninsula_japan_top_export_2020",
            iso3c="QAT",
            evidence_year=2020,
            source_type="local_news",
            source_name="The Peninsula Qatar",
            source_country="Qatar",
            eligible_source=True,
            language="en",
            title="Asian countries top destination of Qatar's exports",
            publication_date="2020-11-29",
            url="https://thepeninsulaqatar.com/article/29/11/2020/Asian-countries-top-destination-of-Qatar%E2%80%99s-exports",
            query_used='"Japan has emerged as a top destination for Qatar\'s export" 2020',
            coverage_topic="Japan as top Qatar export destination in 2020",
            rank_label_original="Japan has emerged as a top destination",
            rank_label_english="Japan emerged as top export destination",
            label_type="incumbent_export_rank",
            explicit_rank_language=True,
            mentions_incumbent_trade=True,
            mentions_china=True,
            mentions_rank_change_or_displacement=False,
            incumbent_partner_named="Japan",
            excerpt_under_25_words="Japan has emerged as a top destination for Qatar's export.",
            evidence_strength="strong",
            count_for_benchmark=True,
        ),
        EvidenceSeed(
            source_id="qat_psa_qatar_in_figures_2021",
            iso3c="QAT",
            evidence_year=2021,
            source_type="official_statistics",
            source_name="Planning and Statistics Authority",
            source_country="Qatar",
            eligible_source=True,
            language="en",
            title="Qatar in Figures 2021",
            publication_date="2021-01-01",
            url="https://www.psa.gov.qa/en/statistics/Statistical%20Releases/General/QIF/Qatar_in_Figures_36_2021_EN.pdf",
            query_used='site:psa.gov.qa "Qatar in Figures 2021" Japan exports 2020',
            coverage_topic="Official table of top export destinations including Japan",
            rank_label_original="Top 4 destinations of exports",
            rank_label_english="top export destinations",
            label_type="incumbent_export_rank",
            explicit_rank_language=True,
            mentions_incumbent_trade=True,
            mentions_china=True,
            mentions_rank_change_or_displacement=False,
            incumbent_partner_named="Japan",
            excerpt_under_25_words="Top 4 destinations of exports.",
            evidence_strength="moderate",
            count_for_benchmark=True,
        ),
        EvidenceSeed(
            source_id="slb_imf_country_report_exports_destination_2004",
            iso3c="SLB",
            evidence_year=2004,
            source_type="international_report",
            source_name="International Monetary Fund",
            source_country="International",
            eligible_source=False,
            language="en",
            title="Solomon Islands: 2004 Article IV Consultation",
            publication_date="2004-08-01",
            url="https://www.imf.org/external/pubs/ft/scr/2004/cr04255.pdf",
            query_used='"Solomon Islands" "Exports by Country of Destination" Japan 2003',
            coverage_topic="Supplemental export-destination table, not local uptake",
            rank_label_original="Exports by Country of Destination",
            rank_label_english="exports by country of destination",
            label_type="context_only",
            explicit_rank_language=False,
            mentions_incumbent_trade=True,
            mentions_china=True,
            mentions_rank_change_or_displacement=False,
            incumbent_partner_named="Japan",
            excerpt_under_25_words="Solomon Islands: exports by country of destination.",
            evidence_strength="weak",
            count_for_benchmark=False,
            notes="International macro report; retained only to document observation gap in local/public sources.",
        ),
        EvidenceSeed(
            source_id="ago_anba_china_us_exports_2008",
            iso3c="AGO",
            evidence_year=2008,
            source_type="international_news",
            source_name="Agência de Notícias Brasil-Árabe",
            source_country="Brazil",
            eligible_source=False,
            language="pt",
            title="Brasil e China alcançam EUA nas exportações para Angola",
            publication_date="2008-01-14",
            url="https://anba.com.br/brasil-e-china-alcancam-eua-nas-exportacoes-para-angola/",
            query_used='"Angola" "Estados Unidos" "principal destino" "exportações" "China" 2007',
            coverage_topic="Third-country discussion of China surpassing United States in Angolan exports",
            rank_label_original="principal destino",
            rank_label_english="main destination",
            label_type="context_only",
            explicit_rank_language=True,
            mentions_incumbent_trade=True,
            mentions_china=True,
            mentions_rank_change_or_displacement=True,
            incumbent_partner_named="United States",
            excerpt_under_25_words="China ... ultrapassou os Estados Unidos como principal destino.",
            evidence_strength="weak",
            count_for_benchmark=False,
            notes="Not Angola local or official; retained as context only.",
        ),
        EvidenceSeed(
            source_id="sle_statistics_2013_trade_bulletin",
            iso3c="SLE",
            evidence_year=2013,
            source_type="official_statistics",
            source_name="Statistics Sierra Leone",
            source_country="Sierra Leone",
            eligible_source=True,
            language="en",
            title="Foreign Trade Statistics Bulletin 2013",
            publication_date="2013-01-01",
            url="https://www.statistics.sl/images/StatisticsSL/Documents/2013_foreign_trade_statistics_bulletin.pdf",
            query_used='site:statistics.sl "2013_foreign_trade_statistics_bulletin" Belgium China exports',
            coverage_topic="Official statistics conflict with Belgium incumbent; China ranked first in 2012-2013",
            rank_label_original="majority ... exported to China",
            rank_label_english="majority exported to China",
            label_type="conflict_rank",
            explicit_rank_language=True,
            mentions_incumbent_trade=True,
            mentions_china=True,
            mentions_rank_change_or_displacement=False,
            incumbent_partner_named="Belgium",
            excerpt_under_25_words="Majority of Sierra Leone products were exported to China.",
            evidence_strength="moderate",
            count_for_benchmark=False,
            notes="DO_NOT_COUNT: official source conflicts with Belgium-as-incumbent for 2012.",
        ),
        EvidenceSeed(
            source_id="mmr_nation_thailand_second_trade_2014",
            iso3c="MMR",
            evidence_year=2014,
            source_type="regional_news",
            source_name="The Nation Thailand",
            source_country="Thailand",
            eligible_source=False,
            language="en",
            title="Thailand, Myanmar forge 'landmark' MICE deal",
            publication_date="2014-08-20",
            url="https://www.nationthailand.com/international/30241366",
            query_used='"Thailand" "Myanmar\'s second largest trading partner" "2013"',
            coverage_topic="Regional coverage ranks Thailand second, not first, by 2013",
            rank_label_original="Myanmar's second largest trading partner",
            rank_label_english="Myanmar's second-largest trading partner",
            label_type="conflict_rank",
            explicit_rank_language=True,
            mentions_incumbent_trade=True,
            mentions_china=False,
            mentions_rank_change_or_displacement=False,
            incumbent_partner_named="Thailand",
            excerpt_under_25_words="As Myanmar's second largest trading partner.",
            evidence_strength="weak",
            count_for_benchmark=False,
            notes="DO_NOT_COUNT: INELIGIBLE_SOURCE: regional Thai source, not Myanmar local; retained as conflict/context. If direct refetch times out, use the preserved local raw HTML.",
        ),
    ]


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def write_checksums() -> None:
    lines: list[str] = []
    for path in sorted(RAW_DIR.rglob("*")):
        if path.is_file() and path != CHECKSUMS:
            lines.append(f"{sha256(path)}  {path.relative_to(RAW_DIR)}")
    CHECKSUMS.write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_sources_yaml(evidence_rows: list[dict[str, str]]) -> None:
    lines = [
        "# Auto-generated by scripts/diagnostics/collect_ex_top1_salience_sources.py",
        "sources:",
        "  - id: incumbent_salience_moderators",
        '    name: "Displaced-incumbent salience moderators"',
        '    provider: "Local red_trade diagnostics"',
        f'    url: "{evidence_rows[0]["incumbent_rank_source_file"] if evidence_rows else ""}"',
        "    access_method: local_csv",
        "    requires_credentials: false",
        '    license: "Project diagnostic output"',
        '    variables_used: ["incumbent_partner_iso3", "incumbent_export_share", "china_export_share"]',
        '    temporal_coverage: "entry_year - 1 for treated countries"',
        '    geographic_coverage: "No-covariates persistent treated countries"',
        '    unit_of_analysis: "country"',
        '    download_script: "scripts/diagnostics/create_incumbent_salience_variables.R"',
        f'    date_accessed: "{ACCESS_DATE}"',
        '    notes: "Read only; no targets pipeline was run by this collector."',
    ]
    for row in evidence_rows:
        source_id = slugify(row["source_id"])
        notes = row["notes"].replace('"', "'")
        query = row["query_used"].replace('"', "'")
        lines.extend(
            [
                f"  - id: {source_id}",
                f'    name: "{row["source_name"]}"',
                f'    provider: "{row["source_name"]}"',
                f'    url: "{row["url"]}"',
                '    access_method: "web"',
                "    requires_credentials: false",
                '    license: "Original publisher terms"',
                '    variables_used: ["rank_label_original", "publication_date", "excerpt_under_25_words"]',
                f'    temporal_coverage: "{row["publication_date"]}"',
                f'    geographic_coverage: "{row["source_country"]}"',
                '    unit_of_analysis: "source document/article/report"',
                '    download_script: "scripts/diagnostics/collect_ex_top1_salience_sources.py"',
                f'    date_accessed: "{ACCESS_DATE}"',
                f'    raw_file: "{row["raw_file"]}"',
                f'    query_used: "{query}"',
                f'    notes: "{notes}"',
            ]
        )
    SOURCES_YAML.write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_data_dictionary() -> None:
    DATA_DICTIONARY.write_text(
        """# Data Dictionary: Ex-Top1 Salience Benchmark

Generated by `scripts/diagnostics/collect_ex_top1_salience_sources.py` and
`scripts/diagnostics/analyze_ex_top1_salience.R`.

## ex_top1_source_evidence.csv

| Variable | Type | Description |
|---|---|---|
| source_id | str | Stable source identifier. |
| iso3c | str | ISO3 code of treated country. |
| country_name | str | Treated country name from the No-covariates sample. |
| entry_year | int | China treatment entry year. |
| incumbent_partner_name | str | Export partner ranked #1 at `entry_year - 1` in the existing diagnostic. |
| incumbent_partner_iso3 | str | ISO3 code of incumbent partner. |
| incumbent_rank_year | int | Year immediately before China entry. |
| incumbent_rank_source_file | str | Local file used for incumbent identification. |
| incumbent_export_share | numeric | Incumbent export share in `incumbent_rank_year`. |
| china_export_share | numeric | China export share in `incumbent_rank_year`. |
| evidence_year | int | Year of source evidence. |
| source_type | str | Source category. |
| source_name | str | Publisher/source name. |
| source_country | str | Country or scope of source. |
| eligible_source | bool | Whether the source is local/national/official enough for the benchmark. |
| language | str | Source language code. |
| title | str | Source title. |
| publication_date | date | Publication date used for window checks. |
| url | str | Original URL. |
| archive_url | str | Archive URL if used. |
| raw_file | str | Preserved raw local file. |
| query_used | str | Search query used to discover or verify the source. |
| accessed_at | datetime | UTC collection timestamp. |
| coverage_topic | str | Short description of what the source contributes. |
| rank_label_original | str | Short original-language rank/status label. |
| rank_label_english | str | English translation/paraphrase. |
| label_type | str | `incumbent_export_rank`, `displacement`, `trade_coverage`, `broad_trade_partner_rank`, `non_top_rank`, `conflict_rank`, or `context_only`. |
| explicit_rank_language | bool | Whether source has explicit rank/status language. |
| mentions_incumbent_trade | bool | Whether source covers trade with the incumbent. |
| mentions_china | bool | Whether source also mentions China. |
| mentions_rank_change_or_displacement | bool | Whether source says China displaced/replaced/overtook incumbent. |
| incumbent_partner_named | str | Partner named in evidence text. |
| excerpt_under_25_words | str | Short audit excerpt under 25 words. |
| evidence_strength | str | `strong`, `moderate`, or `weak`. |
| count_for_benchmark | bool | Whether source can enter country-level coding after fetch checks. |
| notes | str | Coding and eligibility notes. |

## ex_top1_country_codes.csv

Country-level coding generated in R. Key variables include source counts,
`ex_top1_coverage_code`, `coding_rationale`, and `remaining_gaps`.

## status_cue_vs_ex_top1_coverage.csv

Comparison between original China status-cue salience and this ex-Top1
recoverability benchmark.
""",
        encoding="utf-8",
    )


def write_collection_log(
    sample: list[dict[str, str]],
    incumbent_csv: Path,
    evidence_rows: list[dict[str, str]],
    fetch_meta: list[dict[str, object]],
    search_rows: list[dict[str, str]],
) -> None:
    status_counts: dict[str, int] = {}
    for meta in fetch_meta:
        status = str(meta.get("fetch_status", ""))
        status_counts[status] = status_counts.get(status, 0) + 1

    lines = [
        "# Ex-Top1 Salience Collection Log",
        "",
        f"Generated: {ACCESSED_AT}",
        "",
        "## Scope",
        "",
        "Primary sample: persistent treated countries from the `No covariates` model in",
        f"`{rel(SAMPLE_CSV)}`. The script read {len(sample)} countries directly from that CSV.",
        "",
        "The incumbent partner is read from the latest local diagnostic matching",
        f"`{rel(INCUMBENT_DIR / INCUMBENT_PATTERN)}`. The file used here was",
        f"`{rel(incumbent_csv)}`. No `targets::tar_make()` call was made.",
        "",
        "Source window: `entry_year - 1` through `entry_year + 1`.",
        "",
        "## Fetch Status",
        "",
        "| source_id | iso3c | fetch_status | status_code | raw_file | size_bytes |",
        "| --- | --- | --- | --- | --- | ---: |",
    ]
    for meta in fetch_meta:
        lines.append(
            f"| {meta.get('source_id')} | {meta.get('iso3c')} | "
            f"{meta.get('fetch_status')} | {meta.get('status_code')} | "
            f"{meta.get('raw_file')} | {meta.get('size_bytes', 0)} |"
        )
    lines.extend(
        [
            "",
            f"Fetch status counts: `{json.dumps(status_counts, sort_keys=True)}`.",
            "",
            "## Search Log",
            "",
            f"Search queries are preserved in `{rel(SEARCH_PLAN_CSV)}` and as JSON in",
            f"`{rel(RAW_DIR / 'search_logs' / 'search_plan.json')}`.",
            f"The query log contains {len(search_rows)} country-query rows.",
            "",
            "## Coding Notes",
            "",
            "- A source marked `INELIGIBLE_SOURCE` is retained only as context and never counted.",
            "- A source marked `DO_NOT_COUNT` is preserved but excluded from country-level counters.",
            "- Sources with failed raw fetches are automatically excluded from counters.",
            "- Rank labels use short excerpts to avoid copyright problems.",
            "",
            "The country-level coding and interpretation are generated by",
            "`scripts/diagnostics/analyze_ex_top1_salience.R`.",
        ]
    )
    COLLECTION_LOG.write_text("\n".join(lines) + "\n", encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--acquire",
        action="store_true",
        help="Fetch only coded raw files that are currently absent.",
    )
    parser.add_argument("--timeout", type=int, default=20)
    parser.add_argument("--retries", type=int, default=3)
    parser.add_argument("--backoff", type=float, default=1.0)
    return parser.parse_args()


def main() -> int:
    """Validate the frozen archive and, when explicit, acquire missing raw files.

    The historical derivation helpers above are intentionally not called. The
    source ledger is author-owned, and country aggregation, comparisons, and
    appendix tables are now reconstructed by ``targets``.
    """

    args = parse_args()
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    rows = acquisition.validate_frozen_archive(
        root=ROOT,
        ledger_path=EVIDENCE_CSV,
        raw_dir=RAW_DIR,
        manifest_path=CHECKSUMS,
        expected_entries=EXPECTED_MANIFEST_ENTRIES,
        allow_missing=args.acquire,
        allow_unmanifested=args.acquire,
    )
    logging.info(
        "Validated %d source rows and %d raw checksums",
        len(rows),
        EXPECTED_MANIFEST_ENTRIES,
    )
    if not args.acquire:
        logging.info("Read-only check complete; pass --acquire to fetch absent raw files")
        return 0

    frozen_entries = acquisition.read_checksum_manifest(CHECKSUMS, RAW_DIR)
    batch = acquisition.acquire_missing_ledger_files(
        root=ROOT,
        raw_dir=RAW_DIR,
        rows=rows,
        user_agent=USER_AGENT,
        timeout_seconds=args.timeout,
        retries=args.retries,
        backoff_seconds=args.backoff,
        frozen_entries=frozen_entries,
    )
    attempted = [
        result
        for result in batch.results
        if not result.status.startswith("cached_")
    ]
    if batch.staging_dir is not None:
        logging.info("Archived %d new acquisition result(s)", len(attempted))
    else:
        logging.info("All coded raw files already exist; no files were changed")
    blocking = list(filter(acquisition.acquisition_result_is_blocking, attempted))
    return 2 if blocking else 0


if __name__ == "__main__":
    raise SystemExit(main())
