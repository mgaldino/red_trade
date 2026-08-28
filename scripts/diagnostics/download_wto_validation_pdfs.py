#!/usr/bin/env python3
"""Baixa somente os PDFs oficiais listados numa amostra de validação do piloto.

Não descobre URLs, não pagina resultados e não raspa o portal. Os links foram
obtidos na interface pública de download do WTO Documents Online e estão
registrados no CSV passado por ``--sample``.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import logging
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SAMPLE = ROOT / "data" / "processed" / "wto_coauthorship" / "wto_manual_validation_sample_40.csv"
RAW_DIR = ROOT / "data" / "raw" / "wto_coauthorship" / "2026-08-28" / "validation_pdfs"
LOG_DIR = ROOT / "data" / "raw" / "wto_coauthorship" / "2026-08-28"
ALLOWED_HOST = "docs.wto.org"
ALLOWED_PATH = "/dol2fe/Pages/SS/directdoc.aspx"
USER_AGENT = "red-trade-wto-coauthorship-pilot/0.1 (academic research; low-volume manifest download)"

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
LOGGER = logging.getLogger(__name__)


def safe_name(symbol: str, catalogue_id: str) -> str:
    symbol_part = re.sub(r"[^A-Za-z0-9._-]+", "_", symbol).strip("_")
    return f"{catalogue_id}__{symbol_part}.pdf"


def validate_url(url: str) -> None:
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme != "https" or parsed.hostname != ALLOWED_HOST or parsed.path != ALLOWED_PATH:
        raise ValueError(f"URL fora do endpoint permitido: {url}")


def sha256_bytes(content: bytes) -> str:
    return hashlib.sha256(content).hexdigest()


def download(url: str, retries: int = 3) -> tuple[bytes, dict[str, str]]:
    validate_url(url)
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/pdf"})
    last_error: Exception | None = None
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                content = response.read()
                headers = {key.lower(): value for key, value in response.headers.items()}
                if not content.startswith(b"%PDF-"):
                    raise RuntimeError(f"Resposta não é PDF: {headers.get('content-type', '')}")
                return content, headers
        except (urllib.error.URLError, TimeoutError, RuntimeError) as error:
            last_error = error
            if attempt + 1 < retries:
                time.sleep(2**attempt)
    raise RuntimeError(f"Falha após {retries} tentativas: {last_error}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--delay", type=float, default=0.75, help="Pausa entre downloads, em segundos")
    parser.add_argument("--limit", type=int, default=None, help="Limita o número de linhas para teste")
    parser.add_argument("--sample", type=Path, default=DEFAULT_SAMPLE, help="Manifesto CSV explícito")
    parser.add_argument("--batch-name", default="validation", help="Prefixo seguro do log do lote")
    args = parser.parse_args()

    sample = args.sample.resolve()
    if ROOT not in sample.parents:
        raise ValueError("O manifesto deve estar dentro do repositório")
    if not re.fullmatch(r"[A-Za-z0-9_-]+", args.batch_name):
        raise ValueError("--batch-name aceita apenas letras, números, '_' e '-'")
    rows = list(csv.DictReader(sample.open(encoding="utf-8")))
    if args.limit is not None:
        rows = rows[: args.limit]
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    log_path = LOG_DIR / (
        f"{args.batch_name}_download_log_full.json"
        if args.limit is None
        else f"{args.batch_name}_download_log_limit_{args.limit}.json"
    )

    log = {
        "source": "WTO Documents Online",
        "accessed_at": datetime.now(timezone.utc).isoformat(),
        "manifest": str(sample.relative_to(ROOT)),
        "user_agent": USER_AGENT,
        "delay_seconds": args.delay,
        "records": [],
    }

    for index, row in enumerate(rows):
        destination = RAW_DIR / safe_name(row["symbol"], row["catalogue_id"])
        entry = {
            "catalogue_id": row["catalogue_id"],
            "symbol": row["symbol"],
            "url": row["english_url"],
            "path": str(destination.relative_to(ROOT)),
        }
        try:
            content, headers = download(row["english_url"])
            digest = sha256_bytes(content)
            if destination.exists():
                existing = destination.read_bytes()
                if sha256_bytes(existing) != digest:
                    raise RuntimeError("Arquivo existente tem hash diferente; não sobrescrito")
                status = "already_present_same_hash"
            else:
                destination.write_bytes(content)
                status = "downloaded"
            entry.update(
                {
                    "status": status,
                    "bytes": len(content),
                    "sha256": digest,
                    "content_type": headers.get("content-type", ""),
                    "content_disposition": headers.get("content-disposition", ""),
                }
            )
            LOGGER.info("%s %s", status, row["symbol"])
        except Exception as error:  # Mantém o lote e registra falhas individualmente.
            entry.update({"status": "error", "error": str(error)})
            LOGGER.error("erro %s: %s", row["symbol"], error)
        log["records"].append(entry)
        if index + 1 < len(rows):
            time.sleep(args.delay)

    log_path.write_text(json.dumps(log, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    errors = sum(record["status"] == "error" for record in log["records"])
    LOGGER.info("concluído: %d registros, %d erros", len(log["records"]), errors)
    if errors:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
