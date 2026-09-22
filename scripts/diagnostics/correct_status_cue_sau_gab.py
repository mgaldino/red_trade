#!/usr/bin/env python3
"""Focused, append-only collection and recoding for SAU/GAB status-cue windows.

Sources/queries: status_cue_sau_gab_manifest.json alongside this script.
Access: public web/PDF; no credentials. Raw responses are immutable per run.
Run --collect to preserve new responses; run --build --run-dir PATH to recode
from an existing run without network. Robots exclusions and access challenges
are stop conditions. Does not run models or touch targets/manuscripts.
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
import urllib.robotparser
from datetime import datetime, timezone
from pathlib import Path
from html.parser import HTMLParser

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = Path(__file__).with_name("status_cue_sau_gab_manifest.json")
RAW = ROOT / "data/raw/status_cue_salience"
PROCESSED = ROOT / "data/processed/status_cue_salience"
REPORT = ROOT / "quality_reports/status_cue_salience"
USER_AGENT = "RDDTradeResearch/1.0 (status-cue academic source audit)"
DATE = datetime.now(timezone.utc).isoformat(timespec="seconds")
LOG = logging.getLogger(__name__)


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def relative(path):
    return str(path.relative_to(ROOT))


def read_csv(path):
    with path.open(encoding="utf-8-sig", newline="") as stream:
        return list(csv.DictReader(stream))


def write_csv(path, rows, columns=None):
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=columns or list(rows[0]), lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def save_json(path, value):
    with path.open("x", encoding="utf-8") as stream:
        json.dump(value, stream, ensure_ascii=False, indent=2)
        stream.write("\n")


def request(url, path):
    """No overwrites; retry transient network/server errors with backoff."""
    if path.exists():
        raise FileExistsError(path)
    meta = {"url": url, "accessed_at": DATE, "raw_file": "", "sha256": ""}
    for attempt in range(3):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(req, timeout=25) as response:
                body = response.read()
                meta.update(status_code=response.status, content_type=response.headers.get("Content-Type", ""), final_url=response.url)
            with path.open("xb") as stream:
                stream.write(body)
            meta.update(fetch_status="ok", raw_file=relative(path), sha256=digest(path), size_bytes=len(body))
            # A successful HTTP status alone does not establish source access.
            text = body[:15000].lower()
            if any(token in text for token in [b"cf-chl-", b"challenge-platform", b"verify you are human", b"just a moment..."]):
                meta["fetch_status"] = "access_challenge_stop"
            return meta
        except urllib.error.HTTPError as error:
            if error.code >= 500 and attempt < 2:
                time.sleep(2 ** (attempt + 1))
                continue
            meta.update(fetch_status="http_error", status_code=error.code, error=str(error))
            body = error.read()
            if body:
                with path.open("xb") as stream:
                    stream.write(body)
                meta.update(raw_file=relative(path), sha256=digest(path), size_bytes=len(body))
            return meta
        except Exception as error:
            meta.update(fetch_status="network_error", error=repr(error))
            if "CERTIFICATE_VERIFY_FAILED" in repr(error):
                # macOS curl can use the system trust store when Homebrew Python
                # lacks an issuer. Certificate verification stays enabled; no -k.
                command = ["/usr/bin/curl", "--silent", "--show-error", "--location", "--max-time", "30", "--user-agent", USER_AGENT, "--write-out", "\n%{http_code}\n%{content_type}\n%{url_effective}", url]
                response = subprocess.run(command, capture_output=True)
                if response.returncode == 0:
                    body, status, content_type, final_url = response.stdout.rsplit(b"\n", 3)
                    with path.open("xb") as stream:
                        stream.write(body)
                    meta.update(transport="macos_curl_system_trust", status_code=int(status), content_type=content_type.decode(), final_url=final_url.decode(), fetch_status="ok" if int(status) == 200 else "http_error", raw_file=relative(path), sha256=digest(path), size_bytes=len(body))
                    if any(token in body[:15000].lower() for token in [b"cf-chl-", b"challenge-platform", b"verify you are human", b"just a moment..."]):
                        meta["fetch_status"] = "access_challenge_stop"
                    return meta
                meta["curl_error"] = response.stderr.decode(errors="replace")
                return meta
            if attempt < 2:
                time.sleep(2 ** (attempt + 1))
    return meta


def collect(manifest, run_dir, reuse_from=None):
    run_dir.mkdir(parents=True, exist_ok=False)
    save_json(run_dir / "manifest.json", manifest)
    robots = {}
    results = []
    prior = {r["source_id"]: r for r in json.loads((reuse_from / "fetch_results.json").read_text())} if reuse_from else {}
    for source in manifest["sources"]:
        if source["source_id"] in prior and prior[source["source_id"]]["fetch_status"] == "ok":
            result = dict(prior[source["source_id"]])
            assert digest(ROOT / result["raw_file"]) == result["sha256"]
            result["reused_from"] = relative(reuse_from)
            results.append(result)
            save_json(run_dir / (source["source_id"] + ".metadata.json"), result)
            continue
        parts = urllib.parse.urlsplit(source["url"])
        host = f"{parts.scheme}://{parts.netloc}"
        if host not in robots:
            path = run_dir / (parts.netloc.replace(".", "_") + "_robots.txt")
            robots[host] = request(host + "/robots.txt", path)
            time.sleep(1)
        robot = robots[host]
        robot_status = robot["fetch_status"]
        permitted = False
        if robot_status == "ok":
            parser = urllib.robotparser.RobotFileParser()
            parser.parse((ROOT / robot["raw_file"]).read_text(encoding="utf-8", errors="replace").splitlines())
            permitted = parser.can_fetch(USER_AGENT, source["url"])
            robot_status = "allowed" if permitted else "disallowed_stop"
        elif robot.get("status_code") in (404, 410):
            permitted, robot_status = True, "no_robots_file"
        else:
            robot_status = "robots_unavailable_stop"
        if permitted:
            suffix = ".pdf" if ".pdf" in parts.path else ".html"
            result = request(source["url"], run_dir / (source["source_id"] + suffix))
        else:
            result = {"url": source["url"], "fetch_status": robot_status, "accessed_at": DATE, "raw_file": "", "sha256": ""}
        result.update(source_id=source["source_id"], robots_status=robot_status, robots_file=robot.get("raw_file", ""))
        results.append(result)
        save_json(run_dir / (source["source_id"] + ".metadata.json"), result)
        LOG.info("%s: %s (%s)", source["source_id"], result["fetch_status"], robot_status)
        time.sleep(1)
    save_json(run_dir / "fetch_results.json", results)
    save_json(run_dir / "robots_results.json", robots)
    return results


def source_text(result):
    path = ROOT / result["raw_file"]
    if path.suffix == ".pdf":
        return subprocess.check_output(["pdftotext", "-layout", str(path), "-"], text=True)
    class VisibleText(HTMLParser):
        def __init__(self):
            super().__init__(convert_charrefs=True)
            self.parts = []
            self.skip = 0

        def handle_starttag(self, tag, attrs):
            if tag in ("script", "style"):
                self.skip += 1

        def handle_endtag(self, tag):
            if tag in ("script", "style"):
                self.skip = max(0, self.skip - 1)

        def handle_data(self, data):
            if not self.skip:
                self.parts.append(data)

    parser = VisibleText()
    parser.feed(path.read_text(encoding="utf-8", errors="replace"))
    return " ".join(parser.parts)


def normalized(text):
    return re.sub(r"\s+", " ", text).strip()


def build(manifest, run_dir):
    results = {r["source_id"]: r for r in json.loads((run_dir / "fetch_results.json").read_text())}
    evidence_path = PROCESSED / "status_cue_source_evidence.csv"
    original = read_csv(evidence_path)
    columns = list(original[0])
    other_original = [r for r in original if r["iso3c"] not in ("SAU", "GAB")]
    urls = {s["url"] for s in manifest["sources"]}
    evidence = [r for r in original if r["url"] not in urls]
    for row in evidence:
        if row["iso3c"] == "SAU":
            row["entry_year"] = "2013"
            if int(row["publication_date"][:4]) not in (2013, 2014):
                if "SAU_WINDOW_CORRECTION" not in row["notes"]:
                    row["notes"] = "DO_NOT_COUNT: SAU_WINDOW_CORRECTION: published outside 2013-2014 M2/M3 window. " + row["notes"]
                row["notes"] = row["notes"].strip()
                row["evidence_strength"] = "weak"
    supplement = []
    for source in manifest["sources"]:
        result = results[source["source_id"]]
        verified = False
        if result["fetch_status"] == "ok":
            assert digest(ROOT / result["raw_file"]) == result["sha256"]
            text = normalized(source_text(result))
            verified = all(normalized(marker) in text for marker in source["verification_markers"])
        target_window = (2013, 2014) if source["iso3c"] == "SAU" else (2015, 2016) if source["metric_window"] == "M3" else (2017, 2018)
        in_window = int(source["publication_date"][:4]) in target_window
        countable = source["eligible"] and verified and in_window
        row = {column: "" for column in columns}
        row.update({key: str(value) for key, value in source.items() if key in columns})
        row.update(country_name="Saudi Arabia" if source["iso3c"] == "SAU" else "Gabon", entry_year="2013" if source["iso3c"] == "SAU" else "2017", raw_file=result["raw_file"], accessed_at=result["accessed_at"], evidence_strength="strong" if countable else "weak", explicit_rank_language="true", mentions_china_rank_change=str(source["eligible"]).lower(), mentions_displaced_incumbent=str(bool(source.get("displaced_partner_named"))).lower())
        row["notes"] = source["notes"]
        # Legacy country table targets M2 for the two corrected cases; M3-only
        # evidence remains in the source table but is excluded from M2 counters.
        if not countable or source["metric_window"] == "M3":
            reason = "M3_WINDOW_ONLY: outside GAB M2 2017-2018 window. " if countable else "Not eligible or full raw/date/text validation failed. "
            row["notes"] = "DO_NOT_COUNT: " + reason + row["notes"]
        evidence.append(row)
        supplement.append({"source_id": source["source_id"], "iso3c": source["iso3c"], "publication_date": source["publication_date"], "metric_window": source["metric_window"], "source_channel": source["source_channel"], "metric_scope": source["metric_scope"], "eligible_publication": str(source["eligible"]).lower(), "full_raw_verified": str(verified).lower(), "counted_in_window": str(countable).lower(), "fetch_status": result["fetch_status"], "robots_status": result["robots_status"], "raw_file": result["raw_file"], "sha256": result["sha256"], "url": source["url"], "accessed_at": result["accessed_at"]})
    assert [r for r in evidence if r["iso3c"] not in ("SAU", "GAB")] == other_original
    assert len({r["url"] for r in evidence}) == len(evidence)
    write_csv(evidence_path, evidence, columns)
    write_csv(PROCESSED / "status_cue_sau_gab_source_audit.csv", supplement)
    codes_path = PROCESSED / "status_cue_country_codes.csv"
    codes = read_csv(codes_path)
    for row in codes:
        if row["iso3c"] not in ("SAU", "GAB"):
            continue
        selected = [r for r in evidence if r["iso3c"] == row["iso3c"] and r["evidence_strength"] in ("strong", "moderate") and not r["notes"].startswith("DO_NOT_COUNT")]
        n_sources = len({r["source_name"] for r in selected})
        row.update(entry_year="2013" if row["iso3c"] == "SAU" else "2017", n_newspaper_sources_strong=str(len(selected)), n_official_sources_strong="0", n_total_strong_or_moderate=str(len(selected)), has_explicit_export_rank_label=str(any(r["label_type"] == "export_rank" for r in selected)).lower(), has_explicit_generic_trade_partner_label=str(any(r["label_type"] == "generic_trade_partner" for r in selected)).lower(), has_official_uptake="false", has_newspaper_uptake=str(bool(selected)).lower(), salience_code="high" if n_sources >= 2 else "medium" if selected else "unknown", negative_case_candidate="no")
        if row["iso3c"] == "SAU":
            row.update(coding_rationale="No countable local top-rank source recovered in corrected M2/M3 2013-2014 publication window; 2016 sources no longer count. Al Riyadh/SPA reports China second and USA first in calendar-year 2013 merchandise exports, requiring rank-definition reconciliation.", remaining_gaps="Contemporaneous top export-rank/public-cue evidence unresolved; no explicit goods-plus-services source recovered. Rank-direction reversals and retrospective articles are excluded; access gaps preclude a negative case.")
        else:
            row.update(coding_rationale=f"M2 2017-2018: {len(selected)} preserved local news sources across {n_sources} publishers; broad trade-partner labels are separated from export-client wording. M3 2015-2016 is coded separately in status_cue_sau_gab_windows.csv.", remaining_gaps="Sources using total trade are not strict export-rank evidence. L'Union explicitly identifies China as first export client in 2017. The 2016 premier-client source does not explicitly include services and has inconsistent semester/quarter wording; no fully aligned M3 label established.")
    write_csv(codes_path, codes)
    windows = []
    for iso3c, metric, onset in [("SAU", "M2", 2013), ("SAU", "M3", 2013), ("GAB", "M2", 2017), ("GAB", "M3", 2015)]:
        subset = [s for s in supplement if s["iso3c"] == iso3c and s["counted_in_window"] == "true" and s["metric_window"] in (metric, "M2_M3")]
        names = {next(x["source_name"] for x in manifest["sources"] if x["source_id"] == s["source_id"]) for s in subset}
        strict = [s for s in subset if s["metric_scope"] == ("goods_exports" if metric == "M2" else "goods_services_exports")]
        windows.append({"iso3c": iso3c, "metric": metric, "entry_year": onset, "window_start": onset, "window_end": onset+1, "n_counted_public_cue_sources": len(subset), "n_publishers": len(names), "broad_cue_salience": "high" if len(names) >= 2 else "medium" if subset else "unknown", "n_metric_aligned_sources": len(strict), "metric_aligned_evidence": "observed" if strict else "unresolved", "source_ids": ";".join(s["source_id"] for s in subset)})
    write_csv(PROCESSED / "status_cue_sau_gab_windows.csv", windows)
    # Manifest is valid YAML (JSON is a YAML subset); original historical entries
    # stay byte-for-byte in place, with an explicitly delimited focused appendix.
    yaml_path = PROCESSED / "SOURCES.yaml"
    content = yaml_path.read_text(encoding="utf-8").split("\n# BEGIN SAU_GAB_FOCUSED_CORRECTION")[0]
    for source_id in ("sau_argaam_2016_09_11", "sau_general_authority_for_statistics_2016_11_29"):
        pattern = rf"(  - id: {source_id}\n.*?    notes: )[^\n]*"
        content = re.sub(pattern, lambda match: match.group(1) + '"DO_NOT_COUNT: 2026-09-22 correction; publication in 2016 lies outside SAU M2/M3 2013-2014 window. Historical raw preserved."', content, flags=re.S)
    new_yaml = "\n# BEGIN SAU_GAB_FOCUSED_CORRECTION\n"
    for source in manifest["sources"]:
        result = results[source["source_id"]]
        record = {"id": source["source_id"], "name": source["title"], "provider": source["source_name"], "url": source["url"], "access_method": "public_web_download", "license": "Publisher copyright; no redistribution license asserted; retained for internal verification", "download_script": relative(Path(__file__)), "date_accessed": result["accessed_at"][:10], "raw_file": result["raw_file"], "fetch_status": result["fetch_status"], "source_channel": source["source_channel"], "metric_scope": source["metric_scope"], "publication_date": source["publication_date"], "notes": source["notes"]}
        new_yaml += "  - " + json.dumps(record, ensure_ascii=False) + "\n"
    yaml_path.write_text(content + new_yaml, encoding="utf-8")
    summary = {"run_dir": relative(run_dir), "generated_at": DATE, "query_count": len(manifest["queries"]), "candidate_count": len(supplement), "preserved_and_verified": sum(s["full_raw_verified"] == "true" for s in supplement), "windows": windows, "models_run": False, "other_12_countries_unchanged": True}
    (REPORT / "sau_gab_correction_validation.json").write_text(json.dumps(summary, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    old_outputs = [PROCESSED / "status_cue_event_profile_descriptive.csv", PROCESSED / "status_cue_salience_subgroup_fect.csv"]
    write_csv(PROCESSED / "status_cue_legacy_outputs_status.csv", [{"file": relative(path), "sha256": digest(path), "status": "historical_not_current", "reason": "Preserved May 2026 legacy absorbing-sample output. SAU/GAB codes and SAU onset changed; subgroup composition no longer matches. No models or event profiles rerun.", "correction_date": "2026-09-22"} for path in old_outputs])
    def table(rows, fields):
        return "\n".join(["| " + " | ".join(fields) + " |", "| " + " | ".join("---" for _ in fields) + " |"] + ["| " + " | ".join(str(row[field]).replace("|", "/") for field in fields) + " |" for row in rows])
    report = f"""# Correção focal da cobertura de Arábia Saudita e Gabão

Gerado em {DATE}. Coleta pública, sem credenciais; fontes preservadas para verificação interna, sem afirmar licença de redistribuição. Implementação com revisão independente separada.

A Arábia Saudita passa de `high` a `unknown` na janela correta de 2013–2014. O Gabão passa de `unknown` a `high` para o cue público amplo em 2017–2018; uma das duas fontes contadas usa explicitamente destino de exportações. Na janela gabonesa de 2015–2016, há um cue de primeiro cliente (`medium`), mas sua métrica não identifica bens mais serviços.

## Janelas e resultado

Tabela 1. Resultado por país e métrica. M2 designa exportações de bens; M3 designa exportações de bens mais serviços. `broad_cue_salience` aceita rótulos públicos mais amplos, separadamente do alinhamento estrito da métrica. `unknown` não significa ausência de cobertura.

{table(windows, ["iso3c", "metric", "entry_year", "window_end", "n_counted_public_cue_sources", "broad_cue_salience", "n_metric_aligned_sources", "metric_aligned_evidence"])}

Os anos de entrada foram conferidos no arquivo `data/processed/diagnostics/china_top_alternative_cross_country/china_top_first_year_all_four_metrics_wide_2026-05-20.csv`. A correção não modifica esses dados comerciais. A tabela país-nível usa M2 para SAU/GAB; os outros 12 países conservam a codificação e os anos legados. Esta é uma correção focal, não uma harmonização de toda a amostra.

## Fontes e limitações substantivas

- **Arábia Saudita:** Al Riyadh, em 6 de maio de 2014, publica despacho da agência pública Saudi Press Agency sobre estatísticas oficiais de exportações de mercadorias no ano-calendário de 2013. Coloca os Estados Unidos em primeiro (14,12%) e a China em segundo (13,4%). Inclui petróleo; não documenta serviços nem combinação China–Hong Kong. É incompatibilidade que requer reconciliação de fonte/definição, e não autoriza alterar o onset nesta tarefa. Fontes de 2016 antes contadas foram excluídas da janela. SPA/Arab News com a Arábia Saudita como maior parceiro regional da China invertem o sentido do rank e não contam. A busca específica de bens mais serviços não localizou notícia compatível.
- **Gabão, 2017–2018:** Gabonreview, 24 de novembro de 2017, anuncia a China como primeiro parceiro comercial no primeiro semestre de 2017 e o deslocamento da França. Sua métrica é comércio bilateral. L'Union, edição de 8 de junho de 2018, página impressa 4, identifica a China como primeiro cliente das exportações gabonesas de 2017, com aproximadamente 35% (35,1% no corpo/tabela). São duas publicações locais diferentes; não são duas fontes oficiais independentes. A notícia de L'Union atribui os dados a órgãos estatísticos/aduaneiros gaboneses. Seu segundo texto na mesma página, sobre parceria econômica, não foi contado outra vez.
- **Gabão, 2015–2016:** Direct Infos Gabon, 4 de dezembro de 2016, identifica a China como primeiro cliente e cita 14,2% das exportações. A publicação é contemporânea à janela M3, mas não especifica serviços. Há ainda divergência entre semestre no título e trimestre no corpo; o período exato da participação nas exportações não está determinado. Por isso, a fonte comprova um cue público de cliente exportador nessa janela, não uma mudança estritamente M3.

## Coleta e acesso

Foram executadas {len(manifest['queries'])} consultas registradas no manifesto, em árabe, francês e inglês, incluindo imprensa local, agências/fontes oficiais e buscas explícitas de bens mais serviços. Foram selecionados {len(supplement)} candidatos para preservação. {summary['preserved_and_verified']} têm texto e marcadores de data verificados nos arquivos completos; destes, três itens gaboneses são cues positivos. A fonte saudita Al Riyadh é evidência de rank contrário e não entra nos contadores positivos.

Tabela 2. Resultado de acesso e validação dos candidatos. `ok` HTTP não basta: a coluna `full_raw_verified` exige também conteúdo e data compatíveis no arquivo preservado.

{table(supplement, ['source_id', 'fetch_status', 'robots_status', 'full_raw_verified', 'counted_in_window'])}

A tentativa inicial no sandbox falhou por resolução de nomes e foi preservada. A coleta autorizada fora desse limite obteve os três arquivos gaboneses e um HTML da SPA. Na SPA, o HTML é uma estrutura dependente de JavaScript sem o texto/data completos nos marcadores verificados; não foi contado. O `robots.txt` de Arab News devolveu 403, e a coleta parou. Al Riyadh exigiu o repositório normal de certificados do macOS porque o Python local não reconheceu o emissor; o curl manteve a verificação TLS habilitada. Seu robots permitiu a página e o HTML foi preservado. No arquivo de L'Union, robots devolveu 404; não havia regra de exclusão declarada. Nenhum bloqueio, CAPTCHA ou paywall foi contornado.

Info241 retornou 403 na leitura web; um candidato de L'Union em site migrado exibia data de 2024; retrospectivas sauditas de 2016/2018 e gabonesas de 2019 ficaram fora das janelas. Esses candidatos de descoberta não foram contados. Consultas são reproduzíveis como estratégias de descoberta, mas a indexação da busca pode mudar. A reprodução da codificação é offline a partir dos raws.

## Reprodução e validação

```sh
python3 scripts/diagnostics/correct_status_cue_sau_gab.py --build --run-dir {relative(run_dir)}
Rscript scripts/diagnostics/analyze_status_cue_salience_event_study.R --appendix-only
```

Para nova coleta, use `--collect` com um diretório novo; `--reuse-successful-from` pode reutilizar raws previamente obtidos após conferir seus hashes. O coletor legado agora recusa sobrescrever esta correção. O modo R `--appendix-only` não carrega targets, não lê alvos e não estima modelos.

Os raws antigos são preservados; novos downloads e robots têm metadados e SHA-256. Os 12 países fora do escopo são checados contra as linhas de entrada. Os outputs antigos de perfil de evento e estimativas foram preservados e marcados como `historical_not_current` em `status_cue_legacy_outputs_status.csv`; não representam os subgrupos corrigidos, mesmo que os totais high/unknown permaneçam 4/9. Não foram reestimados modelos, não foi rodado targets, e o manuscrito/PDF não foi alterado.

A revisão independente antiga corresponde à versão de maio; seu PASS não se transfere automaticamente para esta correção.
"""
    (REPORT / "sau_gab_correction_2026-09-22.md").write_text(report, encoding="utf-8")
    LOG.info("Built source audit and corrected country codes: %s", summary)


def checksums():
    target = RAW / "checksums.sha256"
    target.write_text("".join(f"{digest(path)}  {path.relative_to(RAW)}\n" for path in sorted(RAW.rglob("*")) if path.is_file() and path != target), encoding="utf-8")


def validate(baseline):
    """Mechanical integrity checks, distinct from independent source review."""
    import io
    checked = {}
    for name in ("status_cue_source_evidence.csv", "status_cue_country_codes.csv", "status_cue_appendix_table.csv"):
        path = PROCESSED / name
        old_text = subprocess.check_output(["git", "show", f"{baseline}:{relative(path)}"], cwd=ROOT, text=True)
        old = list(csv.DictReader(io.StringIO(old_text)))
        current = read_csv(path)
        unaffected = lambda rows: sorted((r for r in rows if r["iso3c"] not in ("SAU", "GAB")), key=lambda row: (row["iso3c"], row.get("url", "")))
        assert unaffected(old) == unaffected(current), f"Other-country changes: {name}"
        checked[name] = {"rows": len(current), "other_12_countries_unchanged": True}
    codes = read_csv(PROCESSED / "status_cue_country_codes.csv")
    assert len(codes) == 14 and len({r["iso3c"] for r in codes}) == 14
    assert all(r["negative_case_candidate"] == "no" for r in codes)
    audit = read_csv(PROCESSED / "status_cue_sau_gab_source_audit.csv")
    assert len(audit) == len({r["source_id"] for r in audit}) == 6
    evidence = read_csv(PROCESSED / "status_cue_source_evidence.csv")
    assert len(evidence) == len({r["url"] for r in evidence})
    for row in audit:
        for key in ("source_id", "iso3c", "publication_date", "metric_window", "source_channel", "metric_scope", "fetch_status", "url", "accessed_at"):
            assert row[key], (row["source_id"], key)
        if row["raw_file"]:
            assert digest(ROOT / row["raw_file"]) == row["sha256"]
        if row["counted_in_window"] == "true":
            assert row["full_raw_verified"] == "true" and row["fetch_status"] == "ok"
        item = next(r for r in evidence if r["url"] == row["url"])
        assert len(item["excerpt_under_25_words"].split()) <= 25
    windows = read_csv(PROCESSED / "status_cue_sau_gab_windows.csv")
    assert len(windows) == len({(r["iso3c"], r["metric"]) for r in windows}) == 4
    for row in windows:
        assert int(row["entry_year"]) == int(row["window_start"])
        assert int(row["window_end"]) == int(row["entry_year"]) + 1
        assert 0 <= int(row["n_metric_aligned_sources"]) <= int(row["n_counted_public_cue_sources"])
    old_checksums = subprocess.check_output(["git", "show", f"{baseline}:{relative(RAW / 'checksums.sha256')}"], cwd=ROOT, text=True)
    for line in old_checksums.splitlines():
        expected, path = line.split("  ", 1)
        assert digest(RAW / path) == expected, f"Old raw changed: {path}"
    for line in (RAW / "checksums.sha256").read_text().splitlines():
        expected, path = line.split("  ", 1)
        assert digest(RAW / path) == expected
    for row in read_csv(PROCESSED / "status_cue_legacy_outputs_status.csv"):
        original = subprocess.check_output(["git", "show", f"{baseline}:{row['file']}"], cwd=ROOT)
        assert hashlib.sha256(original).hexdigest() == row["sha256"] == digest(ROOT / row["file"])
    checks = {"validated_at": DATE, "baseline_commit": baseline, "mechanical_status": "PASS", "csvs": checked, "new_candidates": 6, "windows": 4, "old_raw_files_unchanged": len(old_checksums.splitlines()), "all_current_raw_checksums_pass": True, "legacy_numerical_outputs_unchanged": True, "independent_source_review": "separate; not certified by this check"}
    (REPORT / "sau_gab_integrity_checks.json").write_text(json.dumps(checks, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    LOG.info("Integrity checks: %s", checks)


def main():
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--collect", action="store_true")
    parser.add_argument("--build", action="store_true")
    parser.add_argument("--run-dir", type=Path)
    parser.add_argument("--reuse-successful-from", type=Path)
    parser.add_argument("--validate", action="store_true")
    parser.add_argument("--baseline-ref", default="05ffb40")
    args = parser.parse_args()
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    run_dir = args.run_dir or RAW / "focused_sau_gab" / datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    run_dir = run_dir.resolve()
    if args.collect:
        collect(manifest, run_dir, args.reuse_successful_from.resolve() if args.reuse_successful_from else None)
    if args.build:
        manifest = json.loads((run_dir / "manifest.json").read_text(encoding="utf-8"))
        build(manifest, run_dir)
    if not args.collect and not args.build and not args.validate:
        parser.error("Specify --collect, --build, and/or --validate")
    checksums()
    if args.validate:
        validate(args.baseline_ref)
    if args.collect or args.build:
        LOG.info("Run directory: %s", run_dir)


if __name__ == "__main__":
    main()
