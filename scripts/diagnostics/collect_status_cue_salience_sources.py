#!/usr/bin/env python3
"""Acquire raw HTTP evidence for the public status-cue audit.

The source-evidence CSV is now an author-owned input. This collector validates
the frozen ledger/archive by default and, only with ``--acquire``, fetches raw
files that are absent. It never writes processed coding or appendix tables.

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
import shutil
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone
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
RAW_DIR = ROOT / "data" / "raw" / "status_cue_salience"
PROCESSED_DIR = ROOT / "data" / "processed" / "status_cue_salience"
REPORT_DIR = ROOT / "quality_reports" / "status_cue_salience"

EVIDENCE_CSV = PROCESSED_DIR / "status_cue_source_evidence.csv"
COUNTRY_CSV = PROCESSED_DIR / "status_cue_country_codes.csv"
SOURCES_YAML = PROCESSED_DIR / "SOURCES.yaml"
DATA_DICTIONARY = PROCESSED_DIR / "DATA_DICTIONARY.md"
COLLECTION_LOG = REPORT_DIR / "collection_log.md"
CHECKSUMS = RAW_DIR / "checksums.sha256"
EXPECTED_MANIFEST_ENTRIES = 89

ACCESSED_AT = datetime.now(timezone.utc).replace(microsecond=0).isoformat()
HTTP_TIMEOUT_SECONDS = 12
USER_AGENT = (
    "RDD-Trade status cue salience collector/1.0 "
    "(academic reproducibility; contact: local project maintainer)"
)

EVIDENCE_COLUMNS = [
    "iso3c",
    "country_name",
    "entry_year",
    "evidence_year",
    "source_type",
    "source_name",
    "source_country",
    "language",
    "title",
    "publication_date",
    "url",
    "archive_url",
    "raw_file",
    "query_used",
    "accessed_at",
    "rank_label_original",
    "rank_label_english",
    "label_type",
    "explicit_rank_language",
    "mentions_china_rank_change",
    "mentions_displaced_incumbent",
    "displaced_partner_named",
    "excerpt_under_25_words",
    "evidence_strength",
    "notes",
]

COUNTRY_COLUMNS = [
    "iso3c",
    "country_name",
    "entry_year",
    "n_newspaper_sources_strong",
    "n_official_sources_strong",
    "n_total_strong_or_moderate",
    "has_explicit_export_rank_label",
    "has_explicit_generic_trade_partner_label",
    "has_official_uptake",
    "has_newspaper_uptake",
    "salience_code",
    "negative_case_candidate",
    "coding_rationale",
    "remaining_gaps",
]

OFFICIAL_TYPES = {
    "official",
    "official_pdf",
    "official_statistics",
    "official_speech",
    "government_news",
}
NEWSPAPER_TYPES = {
    "newspaper",
    "national_news_agency",
    "local_news",
    "business_news",
}


@dataclass(frozen=True)
class EvidenceSeed:
    source_id: str
    iso3c: str
    evidence_year: int
    source_type: str
    source_name: str
    source_country: str
    language: str
    title: str
    publication_date: str
    url: str
    query_used: str
    rank_label_original: str
    rank_label_english: str
    label_type: str
    explicit_rank_language: bool
    mentions_china_rank_change: bool
    mentions_displaced_incumbent: bool
    displaced_partner_named: str
    excerpt_under_25_words: str
    evidence_strength: str
    notes: str = ""
    archive_url: str = ""
    count_for_salience: bool = True


@dataclass(frozen=True)
class SearchPlan:
    iso3c: str
    queries: tuple[str, ...]
    notes: str = ""


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
    for path in [RAW_DIR, PROCESSED_DIR, REPORT_DIR, RAW_DIR / "gdelt", RAW_DIR / "search_logs"]:
        path.mkdir(parents=True, exist_ok=True)


def read_primary_sample() -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    with SAMPLE_CSV.open("r", encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
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


def request_url(url: str, path: Path) -> FetchResult:
    path.parent.mkdir(parents=True, exist_ok=True)
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    last_error = ""
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=HTTP_TIMEOUT_SECONDS) as response:
                body = response.read()
                path.write_bytes(body)
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
        except Exception as err:  # noqa: BLE001 - log exact fetch failure for audit
            last_error = repr(err)
            time.sleep(1.5 * (attempt + 1))
    error_path = path.with_suffix(path.suffix + ".error.txt")
    error_path.write_text(last_error, encoding="utf-8")
    return FetchResult(raw_file=rel(error_path), status="error", error=last_error)


def extension_for_url(url: str, content_type: str = "") -> str:
    suffix = Path(urllib.parse.urlparse(url).path).suffix.lower()
    if suffix in {".html", ".htm", ".pdf", ".json", ".txt"}:
        return suffix
    if "pdf" in content_type.lower():
        return ".pdf"
    if "json" in content_type.lower():
        return ".json"
    return ".html"


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")


def fetch_evidence(seed: EvidenceSeed, country_lookup: dict[str, dict[str, str]]) -> tuple[dict[str, str], dict[str, object]]:
    country = country_lookup[seed.iso3c]
    country_dir = RAW_DIR / seed.iso3c / str(seed.evidence_year) / slugify(seed.source_name)
    planned_path = country_dir / f"{slugify(seed.source_id)}.html"
    result = request_url(seed.url, planned_path)
    if result.raw_file and result.status in {"ok", "http_error"}:
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
    if not seed.count_for_salience:
        if not notes.startswith("DO_NOT_COUNT:"):
            notes = f"DO_NOT_COUNT: {notes or 'supplemental evidence for audit only.'}".strip()
        evidence_strength = "weak"
    if result.status != "ok":
        prefix = f"DO_NOT_COUNT: raw fetch status is {result.status}"
        if result.status_code is not None:
            prefix += f" ({result.status_code})"
        notes = f"{prefix}. {notes}".strip()
        evidence_strength = "weak"

    row = {
        "iso3c": seed.iso3c,
        "country_name": country["country_name"],
        "entry_year": country["entry_year"],
        "evidence_year": str(seed.evidence_year),
        "source_type": seed.source_type,
        "source_name": seed.source_name,
        "source_country": seed.source_country,
        "language": seed.language,
        "title": seed.title,
        "publication_date": seed.publication_date,
        "url": seed.url,
        "archive_url": seed.archive_url,
        "raw_file": result.raw_file,
        "query_used": seed.query_used,
        "accessed_at": ACCESSED_AT,
        "rank_label_original": seed.rank_label_original,
        "rank_label_english": seed.rank_label_english,
        "label_type": seed.label_type,
        "explicit_rank_language": str(seed.explicit_rank_language).lower(),
        "mentions_china_rank_change": str(seed.mentions_china_rank_change).lower(),
        "mentions_displaced_incumbent": str(seed.mentions_displaced_incumbent).lower(),
        "displaced_partner_named": seed.displaced_partner_named,
        "excerpt_under_25_words": seed.excerpt_under_25_words,
        "evidence_strength": evidence_strength,
        "notes": notes,
    }
    meta = {
        "source_id": seed.source_id,
        "iso3c": seed.iso3c,
        "url": seed.url,
        "fetch_status": result.status,
        "status_code": result.status_code,
        "content_type": result.content_type,
        "raw_file": result.raw_file,
        "size_bytes": result.size_bytes,
        "error": result.error,
        "accessed_at": ACCESSED_AT,
        "count_for_salience": seed.count_for_salience,
    }
    write_json(country_dir / f"{slugify(seed.source_id)}.metadata.json", meta)
    return row, meta


def gdelt_doc_url(query: str, start_year: int, end_year: int) -> str:
    params = {
        "query": query,
        "mode": "artlist",
        "format": "json",
        "maxrecords": "250",
        "sort": "hybridrel",
        "startdatetime": f"{start_year}0101000000",
        "enddatetime": f"{end_year}1231235959",
    }
    return "https://api.gdeltproject.org/api/v2/doc/doc?" + urllib.parse.urlencode(params)


def run_gdelt_queries(sample: list[dict[str, str]]) -> list[dict[str, object]]:
    """Query GDELT DOC API where the requested event window overlaps 2017+."""
    results: list[dict[str, object]] = []
    gdelt_dir = RAW_DIR / "gdelt"
    for country in sample:
        iso3c = country["iso3c"]
        entry_year = int(country["entry_year"])
        end_year = entry_year + 1
        query = (
            f'"{country["country_name"]}" China '
            '("largest trading partner" OR "largest export market" OR '
            '"main export market" OR "top export destination" OR '
            '"principal socio comercial" OR "premier partenaire commercial")'
        )
        record = {
            "iso3c": iso3c,
            "country_name": country["country_name"],
            "entry_year": entry_year,
            "query": query,
            "api": "GDELT DOC 2.0",
            "coverage_note": (
                "DOC 2.0 article-search coverage is documented as fixed from "
                "2017-01-01 onward; pre-2017 treatment windows are not treated "
                "as covered by this endpoint."
            ),
            "attempted": False,
            "url": "",
            "raw_file": "",
            "fetch_status": "not_covered_by_doc_api",
        }
        if end_year >= 2017:
            start_year = max(entry_year, 2017)
            url = gdelt_doc_url(query, start_year, end_year)
            out = gdelt_dir / iso3c / f"{iso3c.lower()}_{start_year}_{end_year}_doc_api.json"
            result = request_url(url, out)
            record.update(
                {
                    "attempted": True,
                    "url": url,
                    "raw_file": result.raw_file,
                    "fetch_status": result.status,
                    "status_code": result.status_code,
                    "content_type": result.content_type,
                    "size_bytes": result.size_bytes,
                    "error": result.error,
                    "accessed_at": ACCESSED_AT,
                }
            )
        results.append(record)
    write_json(gdelt_dir / "gdelt_doc_query_log.json", results)
    return results


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


def write_csv(path: Path, rows: Iterable[dict[str, str]], columns: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=columns, extrasaction="ignore")
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def strong_or_moderate(row: dict[str, str]) -> bool:
    return row.get("evidence_strength") in {"strong", "moderate"}


def counted(row: dict[str, str]) -> bool:
    return (
        strong_or_moderate(row)
        and row.get("explicit_rank_language") == "true"
        and row.get("mentions_china_rank_change") == "true"
        and not row.get("notes", "").startswith("DO_NOT_COUNT")
    )


def aggregate_country_codes(
    sample: list[dict[str, str]],
    evidence_rows: list[dict[str, str]],
    search_plans: dict[str, SearchPlan],
) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    by_country: dict[str, list[dict[str, str]]] = {}
    for row in evidence_rows:
        by_country.setdefault(row["iso3c"], []).append(row)

    manual_codes = {
        "AGO": (
            "unknown",
            "no",
            "No first-window Angolan local or official source with an auditable top-rank label was recovered; later and third-country sources suggest salience but are not enough for coding.",
            "Need Angolan newspaper/ANGOP or official archive access for 2007-2008.",
        ),
        "GAB": (
            "unknown",
            "no",
            "The located Gabonese source identifies China as first economic partner for 2018 but was published after the first-window boundary, so it is not countable for entry-year uptake.",
            "Need a 2017-2018 Gabonese newspaper or official source, not a later retrospective.",
        ),
        "AUS": (
            "unknown",
            "no",
            "The only fetched first-window Australian news item uses rank language in a Victorian state trade-mission context; it is not countable as country-level Australian uptake.",
            "Need a national Australian official or media source for 2010-2011 with an auditable country-level rank label.",
        ),
        "MMR": (
            "unknown",
            "no",
            "The located contemporaneous rank-label item is a Chinese State Council/Xinhua source, not Myanmar local or official uptake, so it is not countable for country-level salience.",
            "Need Myanmar-language newspaper, Myanmar national agency, or Myanmar official source for 2014-2015.",
        ),
        "MYS": (
            "unknown",
            "no",
            "A contemporaneous MITI/Bernama item coded China as second-largest in 2009, while later official investment material says China became largest since 2009; this is a rank-definition/timing inconsistency, not a clean negative case.",
            "Resolve whether the treatment uses exports, total trade, or China/Hong Kong aggregation.",
        ),
        "PHL": (
            "unknown",
            "no",
            "Contemporaneous Philippine official/news sources found in this pass describe China as a third or lower export market in sectoral/monthly coverage, conflicting with the sample entry rather than proving low salience.",
            "Audit treatment coding against Philippine official annual export rankings and China/Hong Kong aggregation.",
        ),
        "QAT": (
            "medium",
            "no",
            "One strong local newspaper source in 2021 reports that China became Qatar's largest trading partner for two consecutive years.",
            "Need an independent 2021-2022 official or second local source to upgrade to high.",
        ),
        "SLE": (
            "unknown",
            "no",
            "No first-window local/official rank-label source was recovered; later local sources identify China as largest trading partner but outside 2012-2013.",
            "Need Sierra Leone official, Awoko, Concord Times, or State House archive search for 2012-2013.",
        ),
        "SLB": (
            "unknown",
            "no",
            "No contemporaneous 2003-2004 Solomon Islands local/official status-rank uptake was recovered; later sources discuss China as largest export market/trading partner after the diplomatic switch.",
            "Need 2003-2004 Solomon Star/SIBC/government archive access; GDELT DOC API is not useful for this window.",
        ),
    }

    for country in sample:
        iso3c = country["iso3c"]
        rows_i = by_country.get(iso3c, [])
        counted_i = [row for row in rows_i if counted(row)]
        official_i = [row for row in counted_i if row["source_type"] in OFFICIAL_TYPES]
        news_i = [row for row in counted_i if row["source_type"] in NEWSPAPER_TYPES]
        n_total = len(counted_i)
        has_export = any(row["label_type"] == "export_rank" for row in counted_i)
        has_generic = any(row["label_type"] == "generic_trade_partner" for row in counted_i)
        has_official = len(official_i) > 0
        has_news = len(news_i) > 0
        independent_sources = len({row["source_name"] for row in counted_i})

        if iso3c in manual_codes:
            salience_code, negative, rationale, gaps = manual_codes[iso3c]
        elif (
            n_total >= 2
            and independent_sources >= 2
            and (len(news_i) >= 1 or len(official_i) >= 1)
        ) or (len(news_i) >= 1 and len(official_i) >= 1):
            salience_code = "high"
            negative = "no"
            labels = sorted({row["rank_label_english"] for row in counted_i if row["rank_label_english"]})
            rationale = (
                f"{n_total} strong/moderate independent first-window sources use explicit rank language"
                + (f" ({'; '.join(labels[:3])})." if labels else ".")
            )
            gaps = "No major gap for salience coding; still verify archived raw files before manuscript use."
        elif n_total >= 1:
            salience_code = "medium"
            negative = "no"
            rationale = "One strong/moderate first-window source uses explicit rank language."
            gaps = "Need a second independent first-window source to classify as high."
        else:
            plan = search_plans.get(iso3c)
            salience_code = "unknown"
            negative = "no"
            rationale = "No countable first-window source with explicit top-rank uptake was recovered."
            gaps = (
                f"Search queries logged: {len(plan.queries) if plan else 0}. "
                "Additional local-language archive work required."
            )

        rows.append(
            {
                "iso3c": iso3c,
                "country_name": country["country_name"],
                "entry_year": country["entry_year"],
                "n_newspaper_sources_strong": str(len(news_i)),
                "n_official_sources_strong": str(len(official_i)),
                "n_total_strong_or_moderate": str(n_total),
                "has_explicit_export_rank_label": str(has_export).lower(),
                "has_explicit_generic_trade_partner_label": str(has_generic).lower(),
                "has_official_uptake": str(has_official).lower(),
                "has_newspaper_uptake": str(has_news).lower(),
                "salience_code": salience_code,
                "negative_case_candidate": negative,
                "coding_rationale": rationale,
                "remaining_gaps": gaps,
            }
        )
    return rows


def seeds() -> list[EvidenceSeed]:
    return [
        EvidenceSeed(
            source_id="bra_agencia_brasil_2009_05_04",
            iso3c="BRA",
            evidence_year=2009,
            source_type="national_news_agency",
            source_name="Agência Brasil",
            source_country="Brazil",
            language="pt",
            title="China supera Estados Unidos e torna-se maior parceiro comercial do Brasil",
            publication_date="2009-05-04",
            url="https://memoria.ebc.com.br/agenciabrasil/noticia/2009-05-04/china-supera-estados-unidos-e-torna-se-maior-parceiro-comercial-do-brasil",
            query_used='"China supera Estados Unidos" "maior parceiro comercial do Brasil" 2009 Agência Brasil',
            rank_label_original="maior parceiro comercial do país",
            rank_label_english="largest trading partner",
            label_type="generic_trade_partner",
            explicit_rank_language=True,
            mentions_china_rank_change=True,
            mentions_displaced_incumbent=True,
            displaced_partner_named="United States",
            excerpt_under_25_words="Pela primeira vez, a China se consolidou como maior parceiro comercial do país.",
            evidence_strength="strong",
        ),
        EvidenceSeed(
            source_id="bra_mre_resenha_lula_2009_05_19",
            iso3c="BRA",
            evidence_year=2009,
            source_type="official_speech",
            source_name="Ministério das Relações Exteriores / FUNAG",
            source_country="Brazil",
            language="pt",
            title="Resenha de Política Exterior do Brasil, número 104, 1º semestre de 2009",
            publication_date="2009-05-19",
            url="https://www.funag.gov.br/chdd/images/Resenhas/Novas/Resenha_numero_104_1_2009.pdf",
            query_used='site:funag.gov.br 2009 Lula China principal parceiro comercial Brasil Beijing "maior parceiro"',
            rank_label_original="maior parceiro comercial brasileiro",
            rank_label_english="largest Brazilian trading partner",
            label_type="generic_trade_partner",
            explicit_rank_language=True,
            mentions_china_rank_change=True,
            mentions_displaced_incumbent=False,
            displaced_partner_named="",
            excerpt_under_25_words="A China passou a ser, em 2009, o maior parceiro comercial brasileiro.",
            evidence_strength="strong",
        ),
        EvidenceSeed(
            source_id="chl_diario_financiero_2009_01_12",
            iso3c="CHL",
            evidence_year=2009,
            source_type="business_news",
            source_name="Diario Financiero",
            source_country="Chile",
            language="es",
            title="Exportaciones chilenas crecieron sólo 4% en 2008",
            publication_date="2009-01-12",
            url="https://www.df.cl/economia-y-politica/exportaciones-chilenas-crecieron-solo-4-en-2008",
            query_used='"Chile" "China" "principal destino de las exportaciones chilenas" 2009',
            rank_label_original="principal destino de los embarques chilenos en el mundo",
            rank_label_english="main destination for Chilean shipments worldwide",
            label_type="export_rank",
            explicit_rank_language=True,
            mentions_china_rank_change=True,
            mentions_displaced_incumbent=True,
            displaced_partner_named="United States",
            excerpt_under_25_words="China sigue siendo el principal destino de las exportaciones chilenas.",
            evidence_strength="strong",
        ),
        EvidenceSeed(
            source_id="chl_subrei_2009_11_30",
            iso3c="CHL",
            evidence_year=2009,
            source_type="government_news",
            source_name="SUBREI / ProChile",
            source_country="Chile",
            language="es",
            title="Culmina V ronda de negociaciones sobre inversiones entre Chile y China",
            publication_date="2009-11-30",
            url="https://www.subrei.gob.cl/sala-de-prensa/noticias/detalle-noticias/2009/11/30/-culmina-v-ronda-de-negociaciones-sobre-inversiones-entre-chile-y-china",
            query_used='site:subrei.gob.cl China primer socio comercial Chile primer destino exportaciones 2009',
            rank_label_original="primer socio comercial de Chile y primer destino de las exportaciones nacionales",
            rank_label_english="first trading partner and first destination for national exports",
            label_type="export_rank",
            explicit_rank_language=True,
            mentions_china_rank_change=True,
            mentions_displaced_incumbent=False,
            displaced_partner_named="",
            excerpt_under_25_words="China se consolidó como el primer socio comercial de Chile.",
            evidence_strength="strong",
        ),
        EvidenceSeed(
            source_id="aus_dfat_2011_06_29",
            iso3c="AUS",
            evidence_year=2011,
            source_type="government_news",
            source_name="Australian Department of Foreign Affairs and Trade",
            source_country="Australia",
            language="en",
            title="Trade with China Hits $100 billion",
            publication_date="2011-06-29",
            url="https://www.dfat.gov.au/news/media/Pages/trade-with-china-hits-100-billion",
            query_used='site:dfat.gov.au Australia China largest export market 2010 2011',
            rank_label_original="largest two-way trading partner, export market and import source",
            rank_label_english="largest trading partner and export market",
            label_type="export_rank",
            explicit_rank_language=True,
            mentions_china_rank_change=True,
            mentions_displaced_incumbent=False,
            displaced_partner_named="",
            excerpt_under_25_words="China was Australia's largest two-way trading partner, export market and import source in 2010.",
            evidence_strength="strong",
        ),
        EvidenceSeed(
            source_id="aus_abc_2010_05_12",
            iso3c="AUS",
            evidence_year=2010,
            source_type="national_news_agency",
            source_name="ABC News",
            source_country="Australia",
            language="en",
            title="Brumby visits China, UAE on trade mission",
            publication_date="2010-05-12",
            url="https://www.abc.net.au/news/2010-05-12/brumby-visits-china-uae-on-trade-mission/431664",
            query_used='"China" "Australia" "biggest export market" "2010"',
            rank_label_original="biggest export market",
            rank_label_english="biggest export market",
            label_type="export_rank",
            explicit_rank_language=True,
            mentions_china_rank_change=True,
            mentions_displaced_incumbent=False,
            displaced_partner_named="",
            excerpt_under_25_words="China's crucial, [our] biggest export market.",
            evidence_strength="weak",
            notes="DO_NOT_COUNT: rank language appears in a Victorian state trade-mission story and does not verify national Australian uptake.",
            count_for_salience=False,
        ),
        EvidenceSeed(
            source_id="mys_miti_2010_01_01",
            iso3c="MYS",
            evidence_year=2010,
            source_type="government_news",
            source_name="MITI / Bernama",
            source_country="Malaysia",
            language="en",
            title="Ministry of Investment, Trade and Industry page on China-ASEAN FTA",
            publication_date="2010-01-07",
            url="https://www.miti.gov.my/index.php/pages/view/1446",
            query_used='Malaysia China largest trading partner 2009 2010 official Bernama "largest trading partner"',
            rank_label_original="second largest trading partner; second largest export market",
            rank_label_english="second-largest trading partner and export market",
            label_type="non_top_rank",
            explicit_rank_language=True,
            mentions_china_rank_change=False,
            mentions_displaced_incumbent=False,
            displaced_partner_named="",
            excerpt_under_25_words="China is now Malaysia's second largest trading partner.",
            evidence_strength="moderate",
            notes="DO_NOT_COUNT: contemporaneous official-source rank language does not code China as the top partner.",
        ),
        EvidenceSeed(
            source_id="phl_gma_2006_02_09",
            iso3c="PHL",
            evidence_year=2006,
            source_type="local_news",
            source_name="GMA News Online / BusinessWorld",
            source_country="Philippines",
            language="en",
            title="China emerging market for semiconductor, electronics exports",
            publication_date="2006-03-05",
            url="https://www.gmanetwork.com/news/money/content/1492/china-emerging-market-for-semiconductor-electronics-exports/story/",
            query_used='Philippines 2005 China largest export market number one export destination local newspaper official 2006',
            rank_label_original="third biggest destination",
            rank_label_english="third-biggest destination",
            label_type="non_top_rank",
            explicit_rank_language=True,
            mentions_china_rank_change=False,
            mentions_displaced_incumbent=False,
            displaced_partner_named="",
            excerpt_under_25_words="China has now become the third biggest destination for electronics and semiconductor exports.",
            evidence_strength="moderate",
            notes="DO_NOT_COUNT: sectoral rank; useful for auditing treatment/rank definition, not public top-status uptake.",
        ),
        EvidenceSeed(
            source_id="phl_psa_2005_12",
            iso3c="PHL",
            evidence_year=2005,
            source_type="official_statistics",
            source_name="Philippine Statistics Authority",
            source_country="Philippines",
            language="en",
            title="Merchandise Export Performance: December 2005",
            publication_date="2006-02-10",
            url="https://psa.gov.ph/content/merchandise-export-performance-december-2005",
            query_used='site:psa.gov.ph Philippines 2005 China top export market largest export destination exports 2005 China',
            rank_label_original="Other top markets; China accounting for 9.7 percent",
            rank_label_english="top market list, not top-ranked China",
            label_type="non_top_rank",
            explicit_rank_language=True,
            mentions_china_rank_change=False,
            mentions_displaced_incumbent=False,
            displaced_partner_named="",
            excerpt_under_25_words="Exports to People's Republic of China accounted for 9.7 percent.",
            evidence_strength="moderate",
            notes="DO_NOT_COUNT: monthly official export release does not identify China as top export destination.",
        ),
        EvidenceSeed(
            source_id="ury_montevideo_2013_09_27",
            iso3c="URY",
            evidence_year=2013,
            source_type="local_news",
            source_name="Montevideo Portal",
            source_country="Uruguay",
            language="es",
            title="Balanza comercial Uruguay-China",
            publication_date="2013-09-27",
            url="https://www.montevideo.com.uy/Noticias/Balanza-comercial-Uruguay-China-uc214666",
            query_used='Uruguay China principal socio comercial 2013 Uruguay XXI informe oficial 2014',
            rank_label_original="principal socio comercial",
            rank_label_english="main trading partner",
            label_type="generic_trade_partner",
            explicit_rank_language=True,
            mentions_china_rank_change=True,
            mentions_displaced_incumbent=False,
            displaced_partner_named="",
            excerpt_under_25_words='China ya asumió su rol de "principal socio comercial" de Uruguay.',
            evidence_strength="strong",
        ),
        EvidenceSeed(
            source_id="ury_mrree_2013_02_04",
            iso3c="URY",
            evidence_year=2013,
            source_type="government_news",
            source_name="Ministerio de Relaciones Exteriores",
            source_country="Uruguay",
            language="es",
            title="Uruguay y China celebran 25 años de relaciones diplomáticas",
            publication_date="2013-02-04",
            url="https://www.gub.uy/ministerio-relaciones-exteriores/comunicacion/noticias/uruguay-y-china-celebran-25-anos-relaciones-diplomaticas",
            query_used='site:gub.uy ministerio relaciones exteriores China principal socio comercial Uruguay 2013',
            rank_label_original="principal socio comercial de Uruguay",
            rank_label_english="main trading partner of Uruguay",
            label_type="generic_trade_partner",
            explicit_rank_language=True,
            mentions_china_rank_change=True,
            mentions_displaced_incumbent=False,
            displaced_partner_named="",
            excerpt_under_25_words="China es el principal socio comercial de Uruguay.",
            evidence_strength="strong",
        ),
        EvidenceSeed(
            source_id="ury_mercopress_2014_02_04",
            iso3c="URY",
            evidence_year=2014,
            source_type="local_news",
            source_name="MercoPress",
            source_country="Uruguay",
            language="en",
            title="China became Uruguay's main trade partner in 2013",
            publication_date="2014-02-04",
            url="https://en.mercopress.com/2014/02/04/china-became-uruguay-s-main-trade-partner-in-2013",
            query_used='"China became Uruguay" "main trade partner" 2013',
            rank_label_original="main trade partner",
            rank_label_english="main trade partner",
            label_type="generic_trade_partner",
            explicit_rank_language=True,
            mentions_china_rank_change=True,
            mentions_displaced_incumbent=False,
            displaced_partner_named="",
            excerpt_under_25_words="China became Uruguay's main trade partner in 2013.",
            evidence_strength="strong",
        ),
        EvidenceSeed(
            source_id="mmr_govcn_xinhua_2014_11_08",
            iso3c="MMR",
            evidence_year=2014,
            source_type="government_news",
            source_name="China State Council / Xinhua",
            source_country="China",
            language="en",
            title="Premier’s official visit to Myanmar to promote bilateral friendship: ambassador",
            publication_date="2014-11-08",
            url="https://english.www.gov.cn/premier/news/2014/11/08/content_281475007266251.htm",
            query_used='Myanmar 2014 China largest trading partner official local newspaper',
            rank_label_original="largest trade partner and import market",
            rank_label_english="largest trade partner",
            label_type="generic_trade_partner",
            explicit_rank_language=True,
            mentions_china_rank_change=True,
            mentions_displaced_incumbent=False,
            displaced_partner_named="",
            excerpt_under_25_words="China stands as the largest trade partner and import market.",
            evidence_strength="weak",
            notes="DO_NOT_COUNT: Chinese official/Xinhua source; not local Myanmar newspaper or Myanmar official uptake.",
            count_for_salience=False,
        ),
        EvidenceSeed(
            source_id="sau_arabnews_2015_12_05",
            iso3c="SAU",
            evidence_year=2015,
            source_type="local_news",
            source_name="Arab News",
            source_country="Saudi Arabia",
            language="en",
            title="Saudi-China trade stands at $70 billion",
            publication_date="2015-12-05",
            url="https://www.arabnews.com/economy/news/845596",
            query_used='site:arabnews.com Saudi China largest trading partner 2015',
            rank_label_original="Saudi Arabia China’s biggest economic partner in the region",
            rank_label_english="China's biggest economic partner in the region",
            label_type="generic_trade_partner",
            explicit_rank_language=True,
            mentions_china_rank_change=True,
            mentions_displaced_incumbent=False,
            displaced_partner_named="",
            excerpt_under_25_words="Saudi Arabia China’s biggest economic partner in the region.",
            evidence_strength="weak",
            notes="DO_NOT_COUNT: source ranks Saudi Arabia as China's regional partner, not China as Saudi Arabia's top partner.",
            count_for_salience=False,
        ),
        EvidenceSeed(
            source_id="sau_argaam_2016_09_11",
            iso3c="SAU",
            evidence_year=2016,
            source_type="business_news",
            source_name="Argaam",
            source_country="Saudi Arabia",
            language="ar",
            title='السعودية: الصين أول شريك تجاري عام 2015.. و"النفط" أهم الصادرات',
            publication_date="2016-09-11",
            url="https://www.argaam.com/ar/article/articledetail/id/444197",
            query_used='"السعودية" "الصين أول شريك تجاري" "2015"',
            rank_label_original="الصين أول شريك تجاري عام 2015",
            rank_label_english="China was the first trading partner in 2015",
            label_type="generic_trade_partner",
            explicit_rank_language=True,
            mentions_china_rank_change=True,
            mentions_displaced_incumbent=True,
            displaced_partner_named="United States",
            excerpt_under_25_words="الصين أول شريك تجاري عام 2015.",
            evidence_strength="strong",
        ),
        EvidenceSeed(
            source_id="sau_stats_2016_11_29",
            iso3c="SAU",
            evidence_year=2016,
            source_type="official_statistics",
            source_name="General Authority for Statistics",
            source_country="Saudi Arabia",
            language="en",
            title='"China" the main destination for Saudi exports',
            publication_date="2016-11-29",
            url="https://www.stats.gov.sa/en/w/-china-the-main-destination-for-saudi-exports-with-a-value-of-sar-6693-million",
            query_used='site:stats.gov.sa China main destination Saudi exports 2015 2016 top exports official',
            rank_label_original="main destination for Saudi exports",
            rank_label_english="main destination for Saudi exports",
            label_type="export_rank",
            explicit_rank_language=True,
            mentions_china_rank_change=True,
            mentions_displaced_incumbent=False,
            displaced_partner_named="",
            excerpt_under_25_words="China is the main destination for exports in Saudi Arabia.",
            evidence_strength="strong",
        ),
        EvidenceSeed(
            source_id="gab_gabonreview_2019_02",
            iso3c="GAB",
            evidence_year=2018,
            source_type="local_news",
            source_name="Gabonreview",
            source_country="Gabon",
            language="fr",
            title="Échanges commerciaux : La Chine toujours au top avec le Gabon",
            publication_date="2019-05-23",
            url="https://www.gabonreview.com/echanges-commerciaux-la-chine-toujours-au-top-avec-le-gabon/",
            query_used="Gabon 2017 Chine premier partenaire commercial 2017 2018 officiel journal Gabon",
            rank_label_original="premier partenaire économique du Gabon",
            rank_label_english="Gabon’s first economic partner",
            label_type="generic_trade_partner",
            explicit_rank_language=True,
            mentions_china_rank_change=True,
            mentions_displaced_incumbent=False,
            displaced_partner_named="",
            excerpt_under_25_words="La Chine a conforté son statut de premier partenaire économique du Gabon en 2018.",
            evidence_strength="moderate",
            notes="Content concerns 2018, but publication appears after the first-window boundary.",
            count_for_salience=False,
        ),
        EvidenceSeed(
            source_id="gab_dgepf_2018",
            iso3c="GAB",
            evidence_year=2018,
            source_type="official_statistics",
            source_name="Direction Générale de l'Économie et de la Politique Fiscale",
            source_country="Gabon",
            language="fr",
            title="Tableau de bord de l'économie: commerce extérieur 2018",
            publication_date="2019-01-01",
            url="https://www.dgepf.ga/object.getObject.do?id=249",
            query_used="site:dgepf.ga Gabon Chine principal partenaire 2018",
            rank_label_original="principal partenaire du Gabon",
            rank_label_english="Gabon’s main partner",
            label_type="generic_trade_partner",
            explicit_rank_language=True,
            mentions_china_rank_change=True,
            mentions_displaced_incumbent=False,
            displaced_partner_named="",
            excerpt_under_25_words="La Chine demeure le principal partenaire du Gabon.",
            evidence_strength="moderate",
            notes="Official statistics; exact publication date needs archive confirmation.",
            count_for_salience=False,
        ),
        EvidenceSeed(
            source_id="kwt_kuna_2018_07_03",
            iso3c="KWT",
            evidence_year=2018,
            source_type="national_news_agency",
            source_name="Kuwait News Agency",
            source_country="Kuwait",
            language="en",
            title="Deep-rooted Kuwaiti-Chinese ties raise trade exchange to USD 12 bln",
            publication_date="2018-07-03",
            url="https://www.kuna.net.kw/ArticleDetails.aspx?id=2735409",
            query_used='site:kuna.net.kw China Kuwait trade 2018 top trade partners KUNA',
            rank_label_original="largest commercial partner",
            rank_label_english="largest commercial partner",
            label_type="generic_trade_partner",
            explicit_rank_language=True,
            mentions_china_rank_change=True,
            mentions_displaced_incumbent=False,
            displaced_partner_named="",
            excerpt_under_25_words="China ranked first as Kuwait's largest commercial partner.",
            evidence_strength="strong",
        ),
        EvidenceSeed(
            source_id="kwt_arabtimes_2019_01",
            iso3c="KWT",
            evidence_year=2019,
            source_type="local_news",
            source_name="Arab Times",
            source_country="Kuwait",
            language="en",
            title="What if Kuwait banned imports from China?",
            publication_date="2020-01-29",
            url="https://www.arabtimesonline.com/news/what-if-kuwait-banned-imports-from-china",
            query_used='"Kuwait" "China" "largest trading partner" "2018"',
            rank_label_original="largest trading partner for Kuwait in 2018",
            rank_label_english="largest trading partner for Kuwait",
            label_type="generic_trade_partner",
            explicit_rank_language=True,
            mentions_china_rank_change=True,
            mentions_displaced_incumbent=False,
            displaced_partner_named="",
            excerpt_under_25_words="China ranks first as the largest trading partner for Kuwait in 2018.",
            evidence_strength="moderate",
            notes="Published after the 2018-2019 first-window period; retained only as retrospective context.",
            count_for_salience=False,
        ),
        EvidenceSeed(
            source_id="qat_peninsula_2021_12_13",
            iso3c="QAT",
            evidence_year=2021,
            source_type="local_news",
            source_name="The Peninsula Qatar",
            source_country="Qatar",
            language="en",
            title="China, a strategic partner of Qatar: Ambassador",
            publication_date="2021-12-13",
            url="https://thepeninsulaqatar.com/article/13/12/2021/china-a-strategic-partner-of-qatar-ambassador",
            query_used="Qatar 2021 China largest trading partner official newspaper 2021 2022",
            rank_label_original="Qatar's largest trading partner for two consecutive years",
            rank_label_english="Qatar’s largest trading partner",
            label_type="generic_trade_partner",
            explicit_rank_language=True,
            mentions_china_rank_change=True,
            mentions_displaced_incumbent=False,
            displaced_partner_named="",
            excerpt_under_25_words="China has become Qatar’s largest trading partner for two consecutive years.",
            evidence_strength="strong",
        ),
    ]


def search_plans() -> dict[str, SearchPlan]:
    plans = [
        SearchPlan(
            "SLB",
            (
                '"Solomon Islands" "China" "largest export market" 2003 2004',
                '"Solomon Islands" "China" "largest trading partner" 2003 2004',
                'site:solomontimes.com "China" "largest trading partner" "Solomon Islands"',
                'site:sibconline.com.sb "China" "largest trading partner" "Solomon Islands"',
            ),
            "No contemporaneous 2003-2004 local/official uptake recovered in open-web pass.",
        ),
        SearchPlan(
            "PHL",
            (
                "Philippines 2005 China largest export market number one export destination local newspaper official 2006",
                'site:psa.gov.ph Philippines 2005 China top export market largest export destination exports 2005 China',
                '"China" "top export market" Philippines 2005',
                '"China" "largest export market" "Philippines" "2005"',
            ),
            "Open-web pass found official/news rank language placing China below first in contemporaneous material.",
        ),
        SearchPlan(
            "AGO",
            (
                'site:jornaldeangola.ao China Angola principal parceiro comercial 2008',
                'site:angop.ao China Angola principal parceiro comercial 2008',
                '"China" "principal parceiro comercial" "Angola" "2008"',
                '"China" "maior parceiro comercial" "Angola" "2008"',
            ),
            "No first-window Angolan local/official top-rank source recovered.",
        ),
        SearchPlan(
            "MYS",
            (
                'Malaysia China largest trading partner 2009 2010 official Bernama "largest trading partner"',
                'site:miti.gov.my China Malaysia largest trading partner 2009 2010',
                '"China" "Malaysia" "largest trading partner" "2009"',
                '"China" "Malaysia" "second largest export market" "2009"',
            ),
            "Contemporaneous MITI/Bernama source found China as second-largest in 2009.",
        ),
        SearchPlan(
            "SLE",
            (
                '"Sierra Leone" "China" "largest trading partner" 2012 2013',
                '"Sierra Leone" "China" "largest export" "2012"',
                'site:awokonewspaper.sl China largest trading partner Sierra Leone 2012 2013',
                'site:statehouse.gov.sl China largest trading partner Sierra Leone 2012 2013',
            ),
            "Later sources found; no first-window local/official source recovered.",
        ),
        SearchPlan(
            "GAB",
            (
                "Gabon 2017 Chine premier partenaire commercial 2017 2018 officiel journal Gabon",
                "site:gabonreview.com Gabon Chine premier partenaire commercial 2018",
                "site:dgepf.ga Gabon Chine principal partenaire 2018",
            ),
            "Sources concern 2018, but exact first-window publication timing requires verification.",
        ),
        SearchPlan(
            "KWT",
            (
                'site:kuna.net.kw China Kuwait trade 2018 top trade partners KUNA',
                '"China topped" "Kuwait" "trade partners" "2018"',
                '"Kuwait" "China" "largest trading partner" "2018"',
            ),
            "KUNA and Kuwaiti local press sources found.",
        ),
        SearchPlan(
            "QAT",
            (
                "Qatar 2021 China largest trading partner official newspaper 2021 2022",
                "site:thepeninsulaqatar.com Qatar China largest trading partner 2021",
                "site:gulf-times.com Qatar China largest trading partner 2022",
            ),
            "One first-window local source found; second independent source pending.",
        ),
    ]
    generic_terms = (
        "China largest export destination",
        "China top export market",
        "China largest trading partner",
        "China main trading partner",
        "China principal partner",
        "China number one export market",
        "maior destino das exportações China",
        "principal parceiro comercial China",
        "mayor destino de exportaciones China",
        "principal socio comercial China",
        "premier partenaire commercial Chine",
        "principal marché d'exportation Chine",
    )
    out = {plan.iso3c: plan for plan in plans}
    for iso3c in [
        "AUS",
        "BRA",
        "CHL",
        "URY",
        "MMR",
        "SAU",
    ]:
        if iso3c not in out:
            out[iso3c] = SearchPlan(iso3c, generic_terms)
    return out


def write_search_logs(sample: list[dict[str, str]], plans: dict[str, SearchPlan]) -> None:
    logs: list[dict[str, object]] = []
    for country in sample:
        plan = plans.get(country["iso3c"], SearchPlan(country["iso3c"], ()))
        logs.append(
            {
                "iso3c": country["iso3c"],
                "country_name": country["country_name"],
                "entry_year": country["entry_year"],
                "queries": list(plan.queries),
                "notes": plan.notes,
                "accessed_at": ACCESSED_AT,
            }
        )
        write_json(RAW_DIR / "search_logs" / f"{country['iso3c'].lower()}_query_plan.json", logs[-1])
    write_json(RAW_DIR / "search_logs" / "all_query_plans.json", logs)


def write_sources_yaml(evidence_rows: list[dict[str, str]], gdelt_rows: list[dict[str, object]]) -> None:
    lines = [
        "# Auto-generated by scripts/diagnostics/collect_status_cue_salience_sources.py",
        "sources:",
        "  - id: gdelt_doc_api",
        '    name: "GDELT DOC 2.0 API"',
        '    provider: "The GDELT Project"',
        '    url: "https://api.gdeltproject.org/api/v2/doc/doc"',
        '    api_docs: "https://blog.gdeltproject.org/doc-2-0-updates-1-5-year-searching-and-updated-mobile-interface/"',
        "    access_method: api",
        "    requires_credentials: false",
        '    license: "GDELT Terms of Use; source articles retain original rights"',
        '    temporal_coverage: "DOC API searchable article coverage documented from 2017-01-01 onward"',
        '    geographic_coverage: "global online news monitored by GDELT"',
        '    unit_of_analysis: "article search result"',
        '    download_script: "scripts/diagnostics/collect_status_cue_salience_sources.py"',
        f'    date_accessed: "{ACCESSED_AT[:10]}"',
        '    notes: "Used only as a supplementary discovery/audit source; pre-2017 treatment windows are documented as not covered by this DOC endpoint."',
    ]
    for row in evidence_rows:
        source_id = slugify(f"{row['iso3c']}_{row['source_name']}_{row['publication_date']}")
        lines.extend(
            [
                f"  - id: {source_id}",
                f'    name: "{row["source_name"]}"',
                f'    provider: "{row["source_name"]}"',
                f'    url: "{row["url"]}"',
                f'    access_method: "web"',
                "    requires_credentials: false",
                '    license: "Original publisher terms"',
                f'    variables_used: ["rank_label_original", "publication_date", "excerpt_under_25_words"]',
                f'    temporal_coverage: "{row["publication_date"]}"',
                f'    geographic_coverage: "{row["source_country"]}"',
                '    unit_of_analysis: "source document/article"',
                '    download_script: "scripts/diagnostics/collect_status_cue_salience_sources.py"',
                f'    date_accessed: "{ACCESSED_AT[:10]}"',
                f'    raw_file: "{row["raw_file"]}"',
                f'    query_used: "{row["query_used"].replace(chr(34), chr(39))}"',
                f'    notes: "{row["notes"].replace(chr(34), chr(39))}"',
            ]
        )
    SOURCES_YAML.write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_data_dictionary() -> None:
    DATA_DICTIONARY.write_text(
        """# Data Dictionary: Status Cue Salience

Generated by `scripts/diagnostics/collect_status_cue_salience_sources.py`.

## status_cue_source_evidence.csv

| Variable | Type | Description | Source | Valid values |
|---|---|---|---|---|
| iso3c | string | ISO 3166-1 alpha-3 country code. | Sample CSV | 3-letter code |
| country_name | string | Country name from the treated-country sample. | Sample CSV | text |
| entry_year | integer | First treated year in the No covariates absorbing C&S sample. | Sample CSV | year |
| evidence_year | integer | Year to which the source evidence applies. | Source coding | entry_year or entry_year + 1 where possible |
| source_type | string | Type of source. | Source coding | official, official_pdf, official_statistics, official_speech, government_news, newspaper, local_news, national_news_agency, business_news |
| source_name | string | Publisher or institution. | Source metadata | text |
| source_country | string | Country of source publisher. | Source metadata | text |
| language | string | Main source language. | Source metadata | ISO-like short label |
| title | string | Source title. | Source metadata | text |
| publication_date | date | Publication date where available. | Source metadata | YYYY-MM-DD or approximate YYYY-MM-DD |
| url | string | Source URL used for collection. | Source metadata | URL |
| archive_url | string | Archive URL, if separately available. | Source metadata | URL or blank |
| raw_file | string | Path to raw downloaded response or error log. | Collector | repository-relative path |
| query_used | string | Query that led to or verifies the source. | Search log | text |
| accessed_at | datetime | UTC timestamp of collection. | Collector | ISO-8601 |
| rank_label_original | string | Rank/status wording in source language. | Manual coding from source | text |
| rank_label_english | string | English translation/paraphrase of label. | Manual coding | text |
| label_type | string | Whether the label refers to export rank, generic trade partner, or non-top rank. | Manual coding | export_rank, generic_trade_partner, non_top_rank |
| explicit_rank_language | boolean | Whether the source uses explicit rank/status language. | Manual coding | true/false |
| mentions_china_rank_change | boolean | Whether the source says China became/is first/top/main in the relevant hierarchy. | Manual coding | true/false |
| mentions_displaced_incumbent | boolean | Whether the source names or implies an incumbent displaced by China. | Manual coding | true/false |
| displaced_partner_named | string | Named displaced partner, if any. | Manual coding | text or blank |
| excerpt_under_25_words | string | Short verification excerpt kept under 25 words. | Manual coding | <=25 words |
| evidence_strength | string | Coder assessment of strength for salience coding. | Manual coding | strong, moderate, weak |
| notes | string | Caveats and non-counting notes. | Manual coding | text |

## status_cue_country_codes.csv

| Variable | Type | Description | Source | Valid values |
|---|---|---|---|---|
| iso3c | string | ISO 3166-1 alpha-3 country code. | Sample CSV | 3-letter code |
| country_name | string | Country name. | Sample CSV | text |
| entry_year | integer | Treatment entry year. | Sample CSV | year |
| n_newspaper_sources_strong | integer | Count of countable strong/moderate newspaper/news-agency sources. | Derived | >=0 |
| n_official_sources_strong | integer | Count of countable strong/moderate official sources. | Derived | >=0 |
| n_total_strong_or_moderate | integer | Count of countable strong/moderate sources with explicit top-rank language. | Derived | >=0 |
| has_explicit_export_rank_label | boolean | Any countable source uses export-destination/export-market rank label. | Derived | true/false |
| has_explicit_generic_trade_partner_label | boolean | Any countable source uses generic trading-partner rank label. | Derived | true/false |
| has_official_uptake | boolean | Any countable official source. | Derived | true/false |
| has_newspaper_uptake | boolean | Any countable news source. | Derived | true/false |
| salience_code | string | Country-level salience code. | Derived/manual | high, medium, low, unknown |
| negative_case_candidate | string | Whether low-salience evidence is broad enough for a negative case. | Manual | yes/no |
| coding_rationale | string | Short rationale for code. | Manual | text |
| remaining_gaps | string | Missing sources or verification needed. | Manual | text |
""",
        encoding="utf-8",
    )


def markdown_table(rows: list[dict[str, str]], columns: list[str]) -> str:
    if not rows:
        return "_No rows._"
    header = "| " + " | ".join(columns) + " |"
    sep = "| " + " | ".join(["---"] * len(columns)) + " |"
    body = []
    for row in rows:
        vals = [str(row.get(col, "")).replace("\n", " ") for col in columns]
        body.append("| " + " | ".join(vals) + " |")
    return "\n".join([header, sep, *body])


def write_collection_log(
    sample: list[dict[str, str]],
    evidence_rows: list[dict[str, str]],
    country_rows: list[dict[str, str]],
    fetch_meta: list[dict[str, object]],
    gdelt_rows: list[dict[str, object]],
) -> None:
    status_counts: dict[str, int] = {}
    for meta in fetch_meta:
        status_counts[str(meta.get("fetch_status", "unknown"))] = status_counts.get(str(meta.get("fetch_status", "unknown")), 0) + 1
    gdelt_attempts = [row for row in gdelt_rows if row.get("attempted")]
    gdelt_not_covered = [row for row in gdelt_rows if not row.get("attempted")]
    summary_cols = ["iso3c", "country_name", "entry_year", "salience_code", "negative_case_candidate", "coding_rationale", "remaining_gaps"]
    fetch_rows = [
        {
            "source_id": str(meta.get("source_id", "")),
            "iso3c": str(meta.get("iso3c", "")),
            "fetch_status": str(meta.get("fetch_status", "")),
            "status_code": str(meta.get("status_code", "")),
            "raw_file": str(meta.get("raw_file", "")),
            "size_bytes": str(meta.get("size_bytes", "")),
        }
        for meta in fetch_meta
    ]
    log = f"""# Status Cue Salience Collection Log

Generated: {ACCESSED_AT}

## Scope

Primary sample: treated persistent countries from the `No covariates` model in
`quality_reports/cross_country_sample/china_top_absorbing_cs_sample_fect_treated_countries.csv`.
The script read {len(sample)} countries directly from that CSV and did not hard-code the sample.

The collection targets public uptake of explicit rank/status language in the treatment entry year
and the following year. It separates export-rank labels from broader trading-partner labels because
the mechanism critique turns on the public cue, not only on the trade-data treatment rule.

## GDELT Coverage Note

GDELT was used only as a supplementary discovery/audit source. The logged DOC API source indicates
article-search coverage from 2017-01-01 onward, so pre-2017 treatment windows were not treated as
adequately covered by the DOC endpoint. This affects Angola, Australia, Brazil, Chile, Malaysia,
Myanmar, Philippines, Saudi Arabia, Sierra Leone, Solomon Islands, and Uruguay. GDELT DOC queries
were attempted for {len(gdelt_attempts)} country windows and marked not covered for {len(gdelt_not_covered)}.

Raw GDELT query log: `data/raw/status_cue_salience/gdelt/gdelt_doc_query_log.json`.

## Source Fetch Status

{markdown_table(fetch_rows, ["source_id", "iso3c", "fetch_status", "status_code", "raw_file", "size_bytes"])}

Fetch status counts: {json.dumps(status_counts, ensure_ascii=False, sort_keys=True)}.

## Country Coding Summary

{markdown_table(country_rows, summary_cols)}

## Interpretation Rules

- `high`: at least two countable strong/moderate independent sources, or one strong news source and one strong official source, use explicit top/main/first rank language in the first two post-entry years.
- `medium`: one countable source uses explicit rank language, or available sources are plausible but not fully local/official/timely.
- `low`: broad documented search finds contemporaneous China-trade coverage but no explicit rank/status uptake.
- `unknown`: source access, date, language, or treatment-rank consistency is too weak to interpret absence.

No country is coded as a `negative_case_candidate` in this first pass. That is deliberate: the strongest
apparent absences for Philippines and Malaysia also raise treatment-rank-definition issues, so they should
not be used as negative cases until the trade-rank coding is reconciled against official national statistics.
"""
    COLLECTION_LOG.write_text(log, encoding="utf-8")


def copy_existing_brazil_raw_if_present() -> None:
    source_dir = ROOT / "data" / "raw" / "mechanism_evidence_china_2009_2011" / "mre_resenhas"
    target_dir = RAW_DIR / "BRA" / "2009" / "existing_mechanism_evidence"
    if source_dir.exists():
        target_dir.mkdir(parents=True, exist_ok=True)
        for path in source_dir.glob("Resenha_numero_104_1_2009.*"):
            target = target_dir / path.name
            if not target.exists():
                shutil.copy2(path, target)


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
    try:
        rows = acquisition.validate_frozen_archive(
            root=ROOT,
            ledger_path=EVIDENCE_CSV,
            raw_dir=RAW_DIR,
            manifest_path=CHECKSUMS,
            expected_entries=EXPECTED_MANIFEST_ENTRIES,
            allow_missing=args.acquire,
            allow_unmanifested=args.acquire,
        )
    except acquisition.FrozenArchiveValidationError as error:
        logging.error("%s", error)
        return 2
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
