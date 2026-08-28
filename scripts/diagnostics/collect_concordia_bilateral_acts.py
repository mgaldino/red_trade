#!/usr/bin/env python3
"""Coleta-piloto de atos do sistema oficial Concórdia (MRE).

Fonte: https://concordia.itamaraty.gov.br/
API: https://aplicacao.itamaraty.gov.br/ApiConcordia/
Acesso: API pública, sem credenciais.

O script preserva cada resposta HTTP JSON sem reserialização, registra os
payloads, cabeçalhos, horários e hashes, e nunca sobrescreve uma execução
anterior. A janela padrão é 2000-2014 e o tipo de data 1 corresponde à data de
celebração, conforme a interface pública do portal.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import logging
import random
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


API_BASE = "https://aplicacao.itamaraty.gov.br/ApiConcordia"
PORTAL_BASE = "https://concordia.itamaraty.gov.br"
SWAGGER_VERSION = "v1-12-0-0"
DEFAULT_PARTNERS = [
    "China",
    "Índia",
    "África do Sul",
    "Argentina",
    "Paraguai",
    "México",
    "Indonésia",
    "Turquia",
    "Uruguai",
]
USER_AGENT = "red-trade-concordia-pilot/1.0 (academic research; read-only)"

PROJECT_ROOT = Path(__file__).resolve().parents[2]
RAW_BASE = PROJECT_ROOT / "data" / "raw" / "concordia_bilateral_acts"

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
)
LOGGER = logging.getLogger("concordia-collector")


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def slugify_partner(name: str) -> str:
    replacements = {
        "Á": "A",
        "á": "a",
        "É": "E",
        "é": "e",
        "Í": "I",
        "í": "i",
        "Ó": "O",
        "ó": "o",
        "Ú": "U",
        "ú": "u",
        "Ç": "C",
        "ç": "c",
        " ": "_",
    }
    return "".join(replacements.get(char, char) for char in name).lower()


def request_bytes(
    url: str,
    method: str = "GET",
    payload: dict[str, Any] | None = None,
    attempts: int = 6,
) -> tuple[bytes, dict[str, Any]]:
    data = None
    headers = {
        "Accept": "application/json",
        "User-Agent": USER_AGENT,
        "Origin": PORTAL_BASE,
    }
    if payload is not None:
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        headers["Content-Type"] = "application/json; charset=utf-8"

    request = urllib.request.Request(
        url=url,
        data=data,
        headers=headers,
        method=method,
    )
    last_error: Exception | None = None
    for attempt in range(1, attempts + 1):
        started_at = utc_now()
        try:
            with urllib.request.urlopen(request, timeout=45) as response:
                raw = response.read()
                metadata = {
                    "url": url,
                    "method": method,
                    "request_payload": payload,
                    "started_at_utc": started_at,
                    "completed_at_utc": utc_now(),
                    "status": response.status,
                    "response_headers": dict(response.headers.items()),
                    "response_bytes": len(raw),
                    "sha256": hashlib.sha256(raw).hexdigest(),
                }
                return raw, metadata
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError) as exc:
            last_error = exc
            if attempt == attempts:
                break
            delay = min(30.0, (2 ** (attempt - 1)) + random.random())
            LOGGER.warning(
                "Falha em %s %s (tentativa %d/%d): %s; aguardando %.1fs",
                method,
                url,
                attempt,
                attempts,
                exc,
                delay,
            )
            time.sleep(delay)
    raise RuntimeError(f"Falha após {attempts} tentativas: {method} {url}") from last_error


def write_new(path: Path, raw: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        raise FileExistsError(f"Recusa a sobrescrever dado bruto: {path}")
    path.write_bytes(raw)


def save_json(path: Path, value: Any) -> None:
    write_new(
        path,
        (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode("utf-8"),
    )


def parse_json(raw: bytes, url: str) -> Any:
    try:
        return json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise RuntimeError(f"Resposta não é JSON UTF-8 válido: {url}") from exc


def collect_catalog(
    run_dir: Path,
    endpoint: str,
    request_log: list[dict[str, Any]],
) -> Any:
    url = f"{API_BASE}{endpoint}"
    raw, metadata = request_bytes(url)
    output = run_dir / "catalog" / f"{endpoint.rsplit('/', maxsplit=1)[-1]}.json"
    write_new(output, raw)
    metadata["saved_path"] = str(output.relative_to(PROJECT_ROOT))
    request_log.append(metadata)
    return parse_json(raw, url)


def collect_search_pages(
    run_dir: Path,
    partner: str,
    partner_id: int,
    start_year: int,
    end_year: int,
    page_size: int,
    request_log: list[dict[str, Any]],
) -> list[int]:
    endpoint = "/Acordo/pesquisa-avancada-acordos"
    url = f"{API_BASE}{endpoint}"
    ids: list[int] = []
    page = 1
    total_pages: int | None = None
    partner_dir = run_dir / "searches" / slugify_partner(partner)

    while total_pages is None or page <= total_pages:
        payload = {
            "IdEnvolvido": [str(partner_id)],
            "TipoData": [
                {
                    "IdTipoData": 1,
                    "DataInicial": f"{start_year}-01-01T00:00:00",
                    "DataFinal": f"{end_year}-12-31T23:59:59",
                }
            ],
            "Pagina": page,
            "TamanhoPagina": page_size,
            "TipoAcordo": "BL,TL,ML",
        }
        raw, metadata = request_bytes(url, method="POST", payload=payload)
        output = partner_dir / f"page_{page:03d}.json"
        write_new(output, raw)
        metadata.update(
            {
                "saved_path": str(output.relative_to(PROJECT_ROOT)),
                "partner": partner,
                "partner_id": partner_id,
            }
        )
        request_log.append(metadata)
        parsed = parse_json(raw, url)
        total_pages = int(parsed.get("TotalPages", 0))
        total_count = int(parsed.get("TotalCount", 0))
        ids.extend(int(item["Id"]) for item in parsed.get("Items", []))
        LOGGER.info(
            "%s: página %d/%d, %d registros no total",
            partner,
            page,
            total_pages,
            total_count,
        )
        page += 1
        time.sleep(0.15)
    return ids


def collect_details(
    run_dir: Path,
    act_ids: list[int],
    request_log: list[dict[str, Any]],
) -> None:
    details_dir = run_dir / "details"
    for index, act_id in enumerate(sorted(set(act_ids)), start=1):
        url = f"{API_BASE}/Acordo/detalhar-acordo/{act_id}"
        raw, metadata = request_bytes(url)
        output = details_dir / f"act_{act_id}.json"
        write_new(output, raw)
        metadata.update(
            {
                "saved_path": str(output.relative_to(PROJECT_ROOT)),
                "act_id": act_id,
            }
        )
        request_log.append(metadata)
        if index % 25 == 0 or index == len(set(act_ids)):
            LOGGER.info("Detalhes coletados: %d/%d", index, len(set(act_ids)))
        time.sleep(0.10)


def write_checksums(run_dir: Path) -> None:
    rows: list[str] = []
    for path in sorted(run_dir.rglob("*")):
        if not path.is_file() or path.name == "checksums.sha256":
            continue
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        rows.append(f"{digest}  {path.relative_to(run_dir)}")
    write_new(run_dir / "checksums.sha256", ("\n".join(rows) + "\n").encode("utf-8"))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--start-year", type=int, default=2000)
    parser.add_argument("--end-year", type=int, default=2014)
    parser.add_argument("--page-size", type=int, default=100)
    parser.add_argument(
        "--run-id",
        default=datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ"),
        help="Identificador imutável da execução (padrão: timestamp UTC).",
    )
    args = parser.parse_args()
    if args.start_year > args.end_year:
        parser.error("--start-year deve ser menor ou igual a --end-year")
    if not 1 <= args.page_size <= 1000:
        parser.error("--page-size deve estar entre 1 e 1000")

    run_dir = RAW_BASE / args.run_id
    if run_dir.exists():
        raise FileExistsError(
            f"A execução {args.run_id} já existe; use outro --run-id para não sobrescrever raw."
        )
    run_dir.mkdir(parents=True)
    request_log: list[dict[str, Any]] = []
    started_at = utc_now()

    LOGGER.info("Coletando especificação oficial e catálogos")
    swagger_url = f"{API_BASE}/swagger/docs/{SWAGGER_VERSION}"
    swagger_raw, swagger_metadata = request_bytes(swagger_url)
    swagger_path = run_dir / f"swagger_{SWAGGER_VERSION}.json"
    write_new(swagger_path, swagger_raw)
    swagger_metadata["saved_path"] = str(swagger_path.relative_to(PROJECT_ROOT))
    request_log.append(swagger_metadata)

    involved = collect_catalog(
        run_dir, "/Acordo/listar-envolvidos", request_log
    )
    collect_catalog(run_dir, "/Acordo/listar-assuntos", request_log)
    collect_catalog(run_dir, "/Acordo/listar-vigencias", request_log)

    involved_map = {str(item["Nome"]).strip(): int(item["Id"]) for item in involved}
    missing_partners = [name for name in DEFAULT_PARTNERS if name not in involved_map]
    if missing_partners:
        raise RuntimeError(f"Partes não encontradas no catálogo: {missing_partners}")

    all_act_ids: list[int] = []
    partner_ids = {name: involved_map[name] for name in DEFAULT_PARTNERS}
    for partner, partner_id in partner_ids.items():
        all_act_ids.extend(
            collect_search_pages(
                run_dir=run_dir,
                partner=partner,
                partner_id=partner_id,
                start_year=args.start_year,
                end_year=args.end_year,
                page_size=args.page_size,
                request_log=request_log,
            )
        )

    LOGGER.info("Coletando detalhes de %d atos únicos", len(set(all_act_ids)))
    collect_details(run_dir, all_act_ids, request_log)

    request_log_path = run_dir / "request_log.json"
    save_json(request_log_path, request_log)
    manifest = {
        "source_name": "Concórdia — Acervo de atos internacionais do Brasil",
        "provider": "Ministério das Relações Exteriores",
        "portal_url": PORTAL_BASE,
        "api_base_url": API_BASE,
        "swagger_version": SWAGGER_VERSION,
        "access_method": "API pública oficial; GET para catálogos/detalhes e POST para pesquisa avançada",
        "credentials_required": False,
        "license": "Não identificada na interface ou no Swagger; dados públicos oficiais",
        "started_at_utc": started_at,
        "completed_at_utc": utc_now(),
        "window": {"start_year": args.start_year, "end_year": args.end_year},
        "partners": partner_ids,
        "page_size": args.page_size,
        "search_type": "Data de celebração (IdTipoData=1)",
        "agreement_types_collected": ["BL", "TL", "ML"],
        "unique_act_ids": len(set(all_act_ids)),
        "search_hits_including_cross_partner_duplicates": len(all_act_ids),
        "raw_is_immutable": True,
        "request_log": str(request_log_path.relative_to(PROJECT_ROOT)),
    }
    save_json(run_dir / "run_manifest.json", manifest)
    write_checksums(run_dir)
    LOGGER.info("Coleta concluída em %s", run_dir)


if __name__ == "__main__":
    main()
