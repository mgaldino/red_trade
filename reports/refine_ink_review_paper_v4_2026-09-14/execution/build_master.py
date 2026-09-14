#!/usr/bin/env python3
"""Consolidate bounded specialist records; never computes paper results."""
from pathlib import Path
import collections
import hashlib
import json

OUT = Path(__file__).resolve().parent
ROOT = OUT.parents[2]
data = json.loads((OUT / "master.json").read_text())
if data.get("delivery"):
    raise SystemExit("Registro finalizado: use finalize_master.py para atualizar a entrega, sem reimportar estados preliminares.")
items = {x["item"]: x for x in data["items"]}
dossiers = ["cross_country", "corpus_pipeline", "sdid", "comparability",
            "domain_note", "corpus_votes_bibliography", "local_fixes", "bibliography_xhigh"]
for name in dossiers:
    path = OUT / f"{name}.json"
    if not path.exists():
        continue
    record = json.loads(path.read_text())
    for finding in record.get("findings", []):
        number = finding.get("item")
        if number not in items:
            continue
        row = items[number]
        row["diagnosis"] = finding.get("status")
        row["evidence"] = finding.get("source_locations", [])
        row["reasoning"] = finding.get("reasoning", "")
        row["solution"] = finding.get("disposition", finding.get("proposed_fix", "See specialist dossier."))
        row["fix_assessment"] = finding.get("proposed_fix_assessment")
        row["checks"] = finding.get("mechanical_checks", record.get("checks_performed", []))
        row.setdefault("dossiers", [])
        if name not in row["dossiers"]:
            row["dossiers"].append(name)
        row["status"] = "Adjudicado; integração/revisão pendente"
        row["specialist_finding"] = finding
if items[31].get("diagnosis"):
    items[31]["diagnosis"] = "PARTIAL"
    items[31]["reasoning"] = (
        "A descrição das covariáveis é insuficiente. O código usa abs(US-country), "
        "mas no suporte observado US>=country e o diferencial coincide com a "
        "diferença assinada. A inferência inicial do especialista sobre ausência "
        "de colinearidade foi rejeitada. O papel da residualização synthdid é "
        "objeto da revisão independente. A principal não usa covariáveis."
    )
    items[31]["orchestrator_override"] = "orchestrator_decisions.md; verify_power_identity.R; verify_power_identity.log"
if items[15].get("diagnosis"):
    items[15]["status"] = "Pendente: autorizar implementação e execução de novos targets"
    items[15]["authorization_needed"] = ["Implementar e executar o quadro país-ano no grafo targets, sem reestimar modelos."]
if items[25].get("diagnosis"):
    items[25]["status"] = "Nota explicativa entregue; decisão substantiva reservada ao autor"
    items[25]["changed_files"] = ["domain_note.md", "domain_note.json"]
data["items"] = [items[i] for i in sorted(items)]
data["adjudication_counts"] = dict(collections.Counter(x.get("diagnosis") or "PENDING" for x in data["items"]))
data["orchestrator_decisions"] = "orchestrator_decisions.md"
(OUT / "master.json").write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n")
lines = ["# Matriz de resposta aos 23 itens selecionados", "",
         "Referência congelada em `baseline/`; identidade em `baseline_manifest.json`. "
         "As propostas dos especialistas foram adjudicadas antes da integração. "
         "As decisões do orquestrador prevalecem sobre propostas rejeitadas nos dossiês.", "",
         "| Item | Adjudicação | Responsável/configuração | Estado |", "|---:|---|---|---|"]
for row in data["items"]:
    lines.append(f"| {row['item']} | {row.get('diagnosis') or 'Pendente'} | {row['owner']}: {row['model']} {row['effort']} | {row['status']} |")
for row in data["items"]:
    lines += ["", f"## Item {row['item']}", "", row.get("comment", "").split("**Feedback**:")[0].strip(), "",
              f"**Diagnóstico:** {row.get('diagnosis') or 'Pendente'}. {row.get('reasoning', '')}", "",
              f"**Estado:** {row['status']}", "",
              "**Evidência localizada:** " + "; ".join(row.get("evidence", [])), "",
              "**Dossiês:** " + ", ".join(f"[{n}.md]({n}.md)" for n in row.get("dossiers", [])), "",
              "**Solução/encaminhamento:** " + str(row.get("solution") or "Pendente"), "",
              "**Verificações:** " + str(row.get("checks") or "Ver dossiê"), "",
              "**Revisão independente:** " + str(row.get("independent_review") or "Pendente"), "",
              "**Limitação remanescente:** " + str(row.get("limitation") or "Ver dossiê e decisões do orquestrador")]
(OUT / "master.md").write_text("\n".join(lines) + "\n")
print(json.dumps(data["adjudication_counts"], ensure_ascii=False))
