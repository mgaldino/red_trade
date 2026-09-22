#!/usr/bin/env python3
"""Submit only the CPSR theory subsections to Pangram 4 and retain all feedback.

The input is the exact anonymous-PDF text saved by
run_pangram_cpsr_anonymous.py. A bulk-job receipt prevents duplicate charges.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import time
from pathlib import Path

from run_pangram_cpsr_anonymous import (
    BASE, INPUT, MODEL, OUT, PDF, ROOT, SECTION_RAW,
    api_session, save_json, sha256, utc_now,
)


PREPARED = OUT / "theory_subsections_submitted.json"
RECEIPT = OUT / "theory_subsections_bulk_receipt.json"
RAW = OUT / "theory_subsections_bulk_response_raw.json"
REPORT = OUT / "theory_subsections_full_report.md"
PARTS = (
    ("formal_model", "2.1 A simple model of public status cues"),
    ("interpretation", "2.2 Interpretation"),
    ("hypothesis", "2.3 Hypothesis"),
)


def extract_parts(text: str) -> list[dict[str, str]]:
    markers = [
        (name, label, re.search(r"(?m)^" + re.escape(label) + r"\b", text))
        for name, label in PARTS
    ]
    end = re.search(r"(?m)^3 Data and Design\s*$", text)
    if any(match is None for _, _, match in markers) or end is None:
        raise ValueError("Expected theory subsection boundaries not found")
    bounds = [match.start() for _, _, match in markers] + [end.start()]
    if bounds != sorted(bounds):
        raise ValueError("Theory subsection boundaries are out of order")
    items = [
        {"id": name, "heading": label, "text": text[bounds[i]:bounds[i + 1]].strip()}
        for i, (name, label, _) in enumerate(markers)
    ]
    if any(len(item["text"].split()) < 50 for item in items):
        raise ValueError("A theory subsection has fewer than 50 words")
    return items


def prepare() -> None:
    if not INPUT.exists():
        raise FileNotFoundError(f"Run main-manuscript preparation first: {INPUT}")
    if RECEIPT.exists() or RAW.exists():
        if not PREPARED.exists():
            raise RuntimeError("Existing Pangram task has no saved input")
        print(f"Existing submitted theory text retained: {PREPARED}")
        return
    text = INPUT.read_text(encoding="utf-8")
    items = extract_parts(text)
    save_json(PREPARED, {
        "source_pdf": str(PDF.relative_to(ROOT)),
        "source_pdf_sha256": sha256(PDF),
        "source_text": str(INPUT.relative_to(ROOT)),
        "source_text_sha256": sha256(INPUT),
        "scope": "Only subsections 2.1, 2.2, and 2.3 of Theory and Hypotheses",
        "items": items,
    })
    print("Prepared theory-only items:", [(x["id"], len(x["text"].split())) for x in items])


def submit() -> None:
    if RECEIPT.exists() or RAW.exists():
        print("Existing theory job/result found; skipping billed submission")
        return
    if not PREPARED.exists():
        prepare()
    prepared = json.loads(PREPARED.read_text(encoding="utf-8"))
    items = [{"id": item["id"], "text": item["text"]} for item in prepared["items"]]
    session = api_session()
    models = session.get(f"{BASE}/models", timeout=30)
    models.raise_for_status()
    if MODEL not in models.json().get("models", []):
        raise RuntimeError(f"{MODEL} is unavailable for this API key")
    response = session.post(f"{BASE}/bulk", json={"items": items, "model": MODEL}, timeout=120)
    if not response.ok:
        raise RuntimeError(f"Pangram bulk HTTP {response.status_code}: {response.text[:1200]}")
    payload = response.json()
    if not payload.get("bulk_id"):
        raise RuntimeError(f"Pangram returned no bulk_id: {payload}")
    save_json(RECEIPT, {
        "submitted_at_utc": utc_now(), "bulk_id": payload["bulk_id"],
        "model": MODEL, "prepared_sha256": sha256(PREPARED),
        "submitted_items": [{"id": item["id"], "words": len(item["text"].split())}
                            for item in prepared["items"]],
        "api_submission_response": payload,
    })
    print(f"Submitted theory-only bulk job {payload['bulk_id']}; receipt saved: {RECEIPT}")


def poll(max_seconds: int = 540) -> None:
    if RAW.exists():
        print(f"Existing complete response retained: {RAW}")
        return
    if not RECEIPT.exists():
        raise RuntimeError("No theory bulk receipt; run submit first")
    bulk_id = json.loads(RECEIPT.read_text(encoding="utf-8"))["bulk_id"]
    session = api_session()
    deadline = time.monotonic() + max_seconds
    while time.monotonic() < deadline:
        response = session.get(f"{BASE}/bulk/{bulk_id}", timeout=60)
        response.raise_for_status()
        status = response.json()
        if status.get("status") in ("succeeded", "partial", "failed"):
            results = session.get(f"{BASE}/bulk/{bulk_id}/results",
                                  params={"offset": 0, "limit": 100}, timeout=120)
            results.raise_for_status()
            save_json(RAW, {"status": status, "results": results.json()})
            print(f"Saved complete theory-only response: {RAW}; status={status['status']}")
            return
        print(f"Pangram theory job: {status.get('status')}", flush=True)
        time.sleep(5)
    raise TimeoutError(f"Pangram theory job still running: {bulk_id}")


def validate_result(name: str, result: dict) -> None:
    if result.get("version", "").split(".")[0] != "4":
        raise ValueError(f"Unexpected Pangram model version for {name}")
    text = result.get("text", "")
    windows = result.get("windows", [])
    if not windows or windows[0]["start_index"] != 0 or windows[-1]["end_index"] != len(text):
        raise ValueError(f"Incomplete segment coverage for {name}")
    if any(text[w["start_index"]:w["end_index"]] != w["text"] for w in windows):
        raise ValueError(f"Segment text/offset mismatch for {name}")
    if any(windows[i]["end_index"] != windows[i + 1]["start_index"]
           for i in range(len(windows) - 1)):
        raise ValueError(f"Segment gap for {name}")
    if abs(sum(result[k] for k in ("fraction_ai", "fraction_ai_assisted", "fraction_human")) - 1) > 0.002:
        raise ValueError(f"Document fractions do not sum to one for {name}")


def report() -> None:
    if not all(path.exists() for path in (PREPARED, RECEIPT, RAW)):
        raise RuntimeError("Prepared text, receipt, and completed response required")
    prepared = json.loads(PREPARED.read_text(encoding="utf-8"))
    receipt = json.loads(RECEIPT.read_text(encoding="utf-8"))
    data = json.loads(RAW.read_text(encoding="utf-8"))
    items = data["results"].get("items", [])
    if data["status"].get("status") != "succeeded" or data["results"].get("failed_items"):
        raise ValueError("Theory bulk job did not complete successfully for all items")
    by_id = {item["id"]: item["result"] for item in items}
    if set(by_id) != {item["id"] for item in prepared["items"]}:
        raise ValueError("Theory response item set differs from submitted item set")
    for name, result in by_id.items():
        validate_result(name, result)
    lines = [
        "# Pangram 4 — subseções da teoria do manuscrito CPSR anônimo",
        "",
        f"Submetido em {receipt['submitted_at_utc']}; bulk ID `{receipt['bulk_id']}`.",
        f"Fonte: `{prepared['source_pdf']}`; SHA-256 `{prepared['source_pdf_sha256']}`.",
        f"Texto exato enviado: [theory_subsections_submitted.json](theory_subsections_submitted.json); SHA-256 `{sha256(PREPARED)}`.",
        f"Resposta integral: [theory_subsections_bulk_response_raw.json](theory_subsections_bulk_response_raw.json); SHA-256 `{sha256(RAW)}`.",
        "Escopo: modelo formal (2.1), interpretação (2.2) e hipótese (2.3). A introdução de 43 palavras da seção de teoria ficou fora dessas três subseções.",
        "",
        "## Resultados nativos por subseção",
        "",
        "| Subseção | Palavras enviadas | Versão | Headline | IA | Assistida | Humana | Segmentos |",
        "|---|---:|---|---|---:|---:|---:|---:|",
    ]
    for item in prepared["items"]:
        result = by_id[item["id"]]
        lines.append(f"| {item['heading']} | {len(item['text'].split()):,} | {result['version']} | "
                     f"{result['headline']} | {result['fraction_ai']:.1%} | "
                     f"{result['fraction_ai_assisted']:.1%} | {result['fraction_human']:.1%} | "
                     f"{len(result['windows'])} |")
    if SECTION_RAW.exists():
        old = json.loads(SECTION_RAW.read_text(encoding="utf-8"))
        whole = next(item["result"] for item in old["results"]["items"]
                     if item["id"] == "Theory and Hypotheses")
        lines += ["", f"Na avaliação anterior da seção inteira *Theory and Hypotheses*, o Pangram classificou {whole['fraction_ai']:.1%} como IA. Aquele número inclui as três subseções e a introdução da teoria."]
    lines += [
        "",
        "## Explicações e todos os segmentos devolvidos",
        "",
        "Cada texto abaixo é reproduzido integralmente da resposta da API, com rótulo, score, confiança, posições e campos da análise de humanização. O JSON bruto mantém também todos os demais campos globais.",
    ]
    for item in prepared["items"]:
        result = by_id[item["id"]]
        lines += ["", f"### {item['heading']}", "", f"Pangram: {result['prediction']}", ""]
        for index, window in enumerate(result["windows"], 1):
            lines += [
                f"#### Segmento {index}",
                "",
                f"- Rótulo: **{window['label']}**; `ai_assistance_score`: **{window['ai_assistance_score']:.4f}**; confiança: {window['confidence']}.",
                f"- Índices: [{window['start_index']}, {window['end_index']}); palavras: {window.get('word_count')}; tokens: {window.get('token_length')}.",
                f"- `is_humanized`: {window.get('is_humanized')}; `humanizer_score`: {window.get('humanizer_score')}.",
                "",
                "```text",
                window["text"].rstrip(),
                "```",
                "",
            ]
    lines += [
        "## Interpretação e limites",
        "",
        "As frações são proporções de caracteres classificados, não probabilidades de autoria. O score de cada segmento mede envolvimento de IA, mas não é a probabilidade do rótulo. O modelo formal contém equações e o texto veio de extração de PDF; ambos podem afetar o classificador. Comparações entre chamadas com contextos diferentes devem ser lidas como diagnósticos, não como prova sobre o processo de escrita.",
        "",
        "- https://docs.pangram.com/api-reference/ai-detection",
        "- https://www.pangram.com/research/model-card/pangram-4",
        "",
    ]
    REPORT.write_text("\n".join(lines), encoding="utf-8")
    print(f"Saved theory-only full report: {REPORT}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("prepare", "submit", "poll", "report", "run"))
    action = parser.parse_args().action
    if action in ("prepare", "run"):
        prepare()
    if action in ("submit", "run"):
        submit()
    if action in ("poll", "run"):
        poll()
    if action in ("report", "run"):
        report()


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
