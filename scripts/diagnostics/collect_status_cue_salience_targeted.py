#!/usr/bin/env python3
"""Archive and rebuild the 15-country public-cue audit, outside targets.

Inputs are the fixed 2026-09-22 inventory, the two frozen source CSVs and
status_cue_targeted_candidates.csv.  Discovery is separate from source capture.
The capture manifest records robots decisions, HTTP status, raw SHA-256 and
the query attached to each candidate.  Rebuild never silently treats a search
snippet or an HTTP error page as source evidence.

Usage:
  python3 scripts/diagnostics/collect_status_cue_salience_targeted.py collect
  python3 scripts/diagnostics/collect_status_cue_salience_targeted.py build
  python3 scripts/diagnostics/collect_status_cue_salience_targeted.py reaud_build
  python3 scripts/diagnostics/collect_status_cue_salience_targeted.py validate
"""
from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path

from collect_status_cue_salience_extension import RobotsCache, fetch_checked, raw_text, sha, stamp, utc_now

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / 'data/processed/status_cue_salience'
RAW = ROOT / 'data/raw/status_cue_salience/targeted_2026'
REPORT = ROOT / 'quality_reports/status_cue_salience'
SEED = ROOT / 'scripts/diagnostics/status_cue_targeted_candidates.csv'
REAUDIT_SEED = ROOT / 'scripts/diagnostics/status_cue_subannual_reaudit_sources.csv'
DISCOVERY = ROOT / 'scripts/diagnostics/status_cue_targeted_discovery_queries.csv'
INVENTORY = REPORT / 'search_inventory_goods_rank_one_2026-09-22.csv'
OLD_FILES = [DATA / 'status_cue_source_evidence.csv', DATA / 'status_cue_source_evidence_extension.csv']
COUNTRY_OLD = [DATA / 'status_cue_country_codes.csv', DATA / 'status_cue_country_codes_extension.csv']
ISO = ['JPN','MYS','PER','SAU','PHL','RUS','KAZ','AGO','COD','MRT','MMR','SLB','SLE','ERI','TKM']
METRICS = {'goods_exports','goods_services_exports','services_exports','two_way_trade_goods','two_way_trade_goods_services','total_trade_unspecified','unspecified'}
ENTITIES = {'mainland_china','china_including_hong_kong','hong_kong','taiwan','greater_china','unclear'}
PERIODS = {'annual','fiscal_year','semester','quarter','month','other'}

def read_csv(path: Path) -> list[dict[str,str]]:
    with path.open(encoding='utf-8-sig', newline='') as file:
        return list(csv.DictReader(file))

def write_csv(path: Path, fields: list[str], rows: list[dict[str,str]]) -> None:
    with path.open('w', encoding='utf-8', newline='') as file:
        out = csv.DictWriter(file, fieldnames=fields, extrasaction='ignore')
        out.writeheader()
        out.writerows(rows)

def relative(path: Path) -> str:
    return str(path.relative_to(ROOT))

def inventory() -> dict[str,dict[str,str]]:
    rows = {r['iso3c']:r for r in read_csv(INVENTORY) if r['iso3c'] in ISO}
    if set(rows) != set(ISO):
        raise ValueError('The requested 15-country inventory is not intact')
    return rows

def candidates() -> list[dict[str,str]]:
    rows = read_csv(SEED)
    ids = set()
    for r in rows:
        if r['source_id'] in ids or r['iso3c'] not in ISO:
            raise ValueError('Duplicate/out-of-sample source: '+r['source_id'])
        ids.add(r['source_id'])
        if r['metric_in_source'] not in METRICS or r['entity_in_source'] not in ENTITIES or r['period_in_source'] not in PERIODS:
            raise ValueError('Invalid metric/entity/period: '+r['source_id'])
        if r['planned_count'] not in {'yes','no'}:
            raise ValueError('Invalid planned_count: '+r['source_id'])
    return rows

def legacy_candidates() -> list[dict[str,str]]:
    output = []
    for path in OLD_FILES:
        for line, old in enumerate(read_csv(path), 2):
            if old['iso3c'] not in ISO:
                continue
            ref = f'{path.name}:{line}'
            source_id = 'old_'+path.stem.replace('status_cue_source_evidence','evidence')+'_'+str(line)
            # These are deliberately explicit adjudications, not automatic rank inference.
            coding = LEGACY_CODING[ref]
            output.append({
                **old, **coding, 'source_id':source_id,
                'publisher_family':coding['publisher_family'],
                'reevaluated_from':ref, 'planned_count':coding['planned_count'],
                'annual_confirmation_source_id':coding.get('annual_confirmation_source_id',''),
                'metric_rule_reason':coding['metric_rule_reason'],
                'query_used':old.get('query_used',''),
            })
    if set(LEGACY_CODING) != {r['reevaluated_from'] for r in output}:
        raise ValueError('Legacy reevaluation coverage drift')
    return output

LEGACY_CODING = {
 'status_cue_source_evidence.csv:10':dict(metric_in_source='two_way_trade_goods',entity_in_source='mainland_china',period_in_source='other',planned_count='no',publisher_family='MITI/Bernama',metric_rule_reason='China was second in January-October 2009; no China-first cue.'),
 'status_cue_source_evidence.csv:11':dict(metric_in_source='goods_exports',entity_in_source='mainland_china',period_in_source='other',planned_count='no',publisher_family='GMA/BusinessWorld',metric_rule_reason='China is third, not first, as destination for semiconductor/electronics exports; the sector-specific rank is also excluded.'),
 'status_cue_source_evidence.csv:12':dict(metric_in_source='goods_exports',entity_in_source='mainland_china',period_in_source='month',planned_count='no',publisher_family='PSA',metric_rule_reason='China was below the top destination; archived response is HTTP 403.'),
 'status_cue_source_evidence.csv:16':dict(metric_in_source='total_trade_unspecified',entity_in_source='mainland_china',period_in_source='other',planned_count='no',publisher_family='Xinhua',metric_rule_reason='Chinese state source cannot establish uptake in Myanmar.'),
 'status_cue_source_evidence.csv:17':dict(metric_in_source='total_trade_unspecified',entity_in_source='mainland_china',period_in_source='other',planned_count='yes',publisher_family='Arab News',metric_rule_reason='Local Saudi newspaper uses China-first partner language within 2010-2016 window.'),
 'status_cue_source_evidence.csv:18':dict(metric_in_source='two_way_trade_goods',entity_in_source='mainland_china',period_in_source='annual',planned_count='yes',publisher_family='Argaam',evidence_strength='strong',metric_rule_reason='Regraded from legacy weak: local Argaam independently reports the Saudi GASTAT 2015 full-year goods-trade rank with explicit China-first headline and values; within 2010-2016 window.'),
 'status_cue_source_evidence.csv:19':dict(metric_in_source='goods_exports',entity_in_source='mainland_china',period_in_source='month',planned_count='no',publisher_family='Saudi GASTAT',metric_rule_reason='November 2016 monthly goods-export rank needs full-year 2016 confirmation.'),
 'status_cue_source_evidence.csv:25':dict(metric_in_source='goods_exports',entity_in_source='mainland_china',period_in_source='annual',planned_count='no',publisher_family='Al Riyadh/SPA',metric_rule_reason='China second in 2013 goods exports; public metric conflicts with two-way rank.'),
 'status_cue_source_evidence.csv:26':dict(metric_in_source='goods_exports',entity_in_source='mainland_china',period_in_source='annual',planned_count='no',publisher_family='SPA',metric_rule_reason='China not first in the reported 2013 goods-export ranking.'),
 'status_cue_source_evidence.csv:27':dict(metric_in_source='total_trade_unspecified',entity_in_source='mainland_china',period_in_source='other',planned_count='no',publisher_family='Arab News',metric_rule_reason='Rank status is not sufficiently explicit in available record; no raw file.'),
 'status_cue_source_evidence_extension.csv:4':dict(metric_in_source='goods_exports',entity_in_source='china_including_hong_kong',period_in_source='annual',planned_count='no',publisher_family='Japan Times',metric_rule_reason='China-plus-Hong-Kong aggregation makes the export-first claim; excluded entity.'),
 'status_cue_source_evidence_extension.csv:5':dict(metric_in_source='two_way_trade_goods',entity_in_source='mainland_china',period_in_source='annual',planned_count='yes',publisher_family='JETRO',metric_rule_reason='Official Japanese 2007 two-way goods rank puts mainland China first.'),
 'status_cue_source_evidence_extension.csv:8':dict(metric_in_source='goods_exports',entity_in_source='mainland_china',period_in_source='annual',planned_count='no',publisher_family='Andina',metric_rule_reason='United States, not China, leads Peru goods exports in 2010.'),
 'status_cue_source_evidence_extension.csv:9':dict(metric_in_source='total_trade_unspecified',entity_in_source='mainland_china',period_in_source='other',planned_count='no',publisher_family='MEF',metric_rule_reason='An error response was archived; statement is unverified in a valid raw.'),
 'status_cue_source_evidence_extension.csv:24':dict(metric_in_source='goods_exports',entity_in_source='mainland_china',period_in_source='annual',planned_count='no',publisher_family='Japan Customs',metric_rule_reason='US led Japan goods exports in 2008; no China-first cue.'),
}

def capture() -> Path:
    inventory()
    items = candidates() + legacy_candidates()
    previous = latest() if (RAW/'latest_manifest.txt').is_file() else {'sources':[]}
    previous_by_id = {r['source_id']:r for r in previous['sources']}
    run = RAW / 'runs' / stamp()
    run.mkdir(parents=True, exist_ok=False)
    robots = RobotsCache(run)
    records = []
    for r in items:
        iso, year, source_id = r['iso3c'], r['publication_date'][:4], r['source_id']
        old = previous_by_id.get(source_id)
        if old and old.get('url') == r['url'] and old.get('raw_file') and (ROOT/old['raw_file']).is_file() and sha(ROOT/old['raw_file']) == old.get('sha256'):
            reused = dict(old)
            if r.get('reevaluated_from'):
                reused['original_accessed_at'] = r.get('accessed_at','')
            records.append(reused)
            print(iso, source_id, 'reused_hash_verified', flush=True)
            continue
        source = ROOT / r['raw_file'] if r.get('reevaluated_from') and r.get('raw_file') else None
        result: dict[str,object]
        body: bytes | None = None
        if source and source.is_file():
            body = source.read_bytes()
            result = {'status':'copied_legacy','original_raw_file':relative(source),'original_sha256':sha(source),'original_accessed_at':r.get('accessed_at',''),'final_url':r['url']}
        elif r.get('reevaluated_from'):
            result = {'status':'legacy_raw_missing','final_url':r['url']}
        else:
            result = fetch_checked(r['url'], robots)
            body = result.pop('body', None) if result.get('status') == 'ok' else None
            result.pop('body', None)
        if body is not None:
            suffix = '.pdf' if body.startswith(b'%PDF') else '.html' if b'<html' in body[:1000].lower() or b'<!doctype' in body[:1000].lower() else '.bin'
            dest = RAW / iso / year / source_id / (stamp()+suffix)
            dest.parent.mkdir(parents=True, exist_ok=True)
            with dest.open('xb') as f: f.write(body)
            result.update(raw_file=relative(dest), sha256=sha(dest), size_bytes=len(body))
        result.update(source_id=source_id, iso3c=iso, url=r['url'], query_used=r.get('query_used',''), accessed_at=utc_now())
        records.append(result)
        print(iso, source_id, result['status'], flush=True)
    discovery = read_csv(DISCOVERY)
    manifest = {'run_at':utc_now(),'inventory':relative(INVENTORY),'inventory_sha256':sha(INVENTORY),'seed':relative(SEED),'seed_sha256':sha(SEED),'discovery_queries':relative(DISCOVERY),'discovery_queries_sha256':sha(DISCOVERY),'sources':records}
    mpath = run / 'manifest.json'
    mpath.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    query_manifest = [{'iso3c':r['iso3c'],'source_id':r['source_id'],'query':r.get('query_used',''),'window':f"{int(inventory()[r['iso3c']]['first_entry'])-3}-{int(inventory()[r['iso3c']]['first_entry'])+3}",'kind':'candidate'} for r in items]
    query_manifest += [{'iso3c':r['iso3c'],'source_id':'','query':r['query_exact'],'window':r['years_targeted'],'kind':'discovery','observed_result':r['observed_result'],'searched_at_utc':r['searched_at_utc']} for r in discovery]
    (run/'query_manifest.json').write_text(json.dumps(query_manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    checksums = []
    for path in sorted({ROOT/r['raw_file'] for r in records if r.get('raw_file')}):
        checksums.append(f'{sha(path)}  {relative(path)}')
    (run/'checksums.sha256').write_text('\n'.join(checksums)+'\n',encoding='utf-8')
    (RAW/'latest_manifest.txt').write_text(relative(mpath)+'\n',encoding='utf-8')
    return mpath

def latest() -> dict:
    path = ROOT / (RAW/'latest_manifest.txt').read_text(encoding='utf-8').strip()
    return json.loads(path.read_text(encoding='utf-8'))

def reaud_capture() -> Path:
    """Preserve the seven prior first cues and proposed annual confirmations."""
    items = read_csv(REAUDIT_SEED)
    prev_path = RAW/'latest_reaudit_manifest.txt'
    previous = json.loads((ROOT/prev_path.read_text(encoding='utf-8').strip()).read_text(encoding='utf-8')) if prev_path.is_file() else {'sources':[]}
    previous_by_id = {r['source_id']:r for r in previous['sources']}
    run = RAW / 'reaudit_runs' / stamp()
    run.mkdir(parents=True, exist_ok=False)
    robots = RobotsCache(run)
    records = []
    for r in items:
        old = previous_by_id.get(r['source_id'])
        if old and old.get('url') == r['url'] and old.get('raw_file') and (ROOT/old['raw_file']).is_file() and sha(ROOT/old['raw_file']) == old.get('sha256'):
            records.append(old)
            print(r['iso3c'],r['source_id'],'reused_hash_verified',flush=True)
            continue
        body = None
        if r.get('existing_raw_file'):
            original = ROOT / r['existing_raw_file']
            if original.is_file():
                body = original.read_bytes()
                result: dict[str,object] = {'status':'copied_legacy','original_raw_file':relative(original),'original_sha256':sha(original),'final_url':r['url']}
            else:
                result = {'status':'legacy_raw_missing','final_url':r['url']}
        else:
            result = fetch_checked(r['url'], robots)
            body = result.pop('body', None) if result.get('status') == 'ok' else None
            result.pop('body', None)
        if body is not None:
            suffix = '.pdf' if body.startswith(b'%PDF') else '.html' if b'<html' in body[:1000].lower() or b'<!doctype' in body[:1000].lower() else '.bin'
            dest = RAW / 'reaudit' / r['iso3c'] / r['publication_date'][:4] / r['source_id'] / (stamp()+suffix)
            dest.parent.mkdir(parents=True,exist_ok=True)
            with dest.open('xb') as file: file.write(body)
            result.update(raw_file=relative(dest),sha256=sha(dest),size_bytes=len(body))
        result.update(source_id=r['source_id'],iso3c=r['iso3c'],url=r['url'],query_used=r['query_used'],accessed_at=utc_now())
        records.append(result)
        print(r['iso3c'],r['source_id'],result['status'],flush=True)
    manifest={'run_at':utc_now(),'seed':relative(REAUDIT_SEED),'seed_sha256':sha(REAUDIT_SEED),'sources':records}
    path=run/'manifest.json'
    path.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    (run/'query_manifest.json').write_text(json.dumps([{'iso3c':r['iso3c'],'source_id':r['source_id'],'query':r['query_used']} for r in items],ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    (run/'checksums.sha256').write_text('\n'.join(f'{sha(ROOT/r["raw_file"])}  {r["raw_file"]}' for r in records if r.get('raw_file'))+'\n',encoding='utf-8')
    (RAW/'latest_reaudit_manifest.txt').write_text(relative(path)+'\n',encoding='utf-8')
    return path

REAUDIT_DECISIONS = {
 'KOR': ('kor_first','kor_annual_2003_joongang','2003-10-24','2003-10-24','Jan-Sep 2003 goods exports; full calendar 2003 exports confirmed by Korea JoongAng Daily on 2004-01-12.'),
 'AUS': ('aus_first','','2007-05-04','2007-05-04','ABC compares rolling twelve months through March 2007; this is an annual window, not a month. Goods versus goods and services is not explicit in the ABC raw.'),
 'CHL': ('chl_first','chl_annual_2007_direcon','2007-02-19','2007-02-19','January 2007 monthly goods-export cue. DIRECON full calendar 2007 table ranks mainland China above the United States among individual countries; EU is a block.'),
 'BRA': ('bra_first','bra_annual_2009','2009-05-04','2009-05-04','Jan-Apr 2009 four-month two-way goods trade; Sao Paulo/Apex reports full 2009 China $36.1bn versus US $35.9bn.'),
 'ZAF': ('zaf_first','','2009-12-11','2009-12-11','Current China-first partner statement in Mail & Guardian is not restricted to a subannual reporting interval.'),
 'URY': ('ury_earlier_2013_05_23','','2013-09-27','2013-05-23','Presidencia quoted current principal-partner status on May 23. Its claim that status began in 2012 conflicts with other official annual figures; record cue date, not verified onset year. July 24 official repeats current status; full 2013 trade later first in MercoPress.'),
 'NZL': ('nzl_first','nzl_annual_2013_statsnz','2013-04-26','2013-04-26','Jan-Mar 2013 quarterly goods-export cue; Statistics New Zealand reports mainland China top destination for full calendar 2013.'),
}

def reaud_build() -> None:
    """Write one auditable decision per country from the archived seven-case raws."""
    manifest_path = ROOT / (RAW/'latest_reaudit_manifest.txt').read_text(encoding='utf-8').strip()
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    if manifest['seed_sha256'] != sha(REAUDIT_SEED):
        raise ValueError('Reaudit seed changed after capture; rerun reaudit_collect')
    seed = {r['source_id']:r for r in read_csv(REAUDIT_SEED)}
    capture = {r['source_id']:r for r in manifest['sources']}
    fields = ['iso3c','old_first_cue_date','first_cue_source_id','first_cue_source_name','first_cue_url','first_cue_raw_file','first_cue_sha256','metric_in_source','period_in_source','period_detail','annual_confirmation_source_id','annual_confirmation_url','annual_confirmation_raw_file','annual_confirmation_sha256','cue_date_under_rule','notes']
    rows=[]
    for iso,(first_id,annual_id,old_date,new_date,notes) in REAUDIT_DECISIONS.items():
        s=seed[first_id]; c=capture[first_id]
        if not c.get('raw_file') or sha(ROOT/c['raw_file']) != c['sha256']:
            raise ValueError('Missing/mismatched first cue raw: '+first_id)
        annual=seed.get(annual_id,{}); ac=capture.get(annual_id,{})
        if annual_id and (not ac.get('raw_file') or sha(ROOT/ac['raw_file']) != ac['sha256']):
            raise ValueError('Missing/mismatched annual raw: '+annual_id)
        rows.append(dict(iso3c=iso,old_first_cue_date=old_date,first_cue_source_id=first_id,first_cue_source_name=s['source_name'],first_cue_url=s['url'],first_cue_raw_file=c['raw_file'],first_cue_sha256=c['sha256'],metric_in_source=s['metric'],period_in_source=s['period'],period_detail=notes.split(';')[0],annual_confirmation_source_id=annual_id,annual_confirmation_url=annual.get('url',''),annual_confirmation_raw_file=ac.get('raw_file',''),annual_confirmation_sha256=ac.get('sha256',''),cue_date_under_rule=new_date,notes=notes))
    write_csv(DATA/'status_cue_subannual_reaudit_2026.csv',fields,rows)

def collection_log() -> None:
    """Render a source-by-source audit trail from the immutable capture manifests."""
    mp = ROOT / (RAW/'latest_manifest.txt').read_text(encoding='utf-8').strip()
    rp = ROOT / (RAW/'latest_reaudit_manifest.txt').read_text(encoding='utf-8').strip()
    m=json.loads(mp.read_text(encoding='utf-8'))
    rm=json.loads(rp.read_text(encoding='utf-8'))
    cap={r['source_id']:r for r in m['sources']}
    ev=read_csv(DATA/'status_cue_source_evidence_targeted.csv')
    country=read_csv(DATA/'status_cue_country_codes_targeted.csv')
    inv=inventory()
    q=read_csv(DISCOVERY)
    lines=['# Busca dirigida: diário de coleta e trilha de auditoria','','Data desta coleta: 2026-09-24 UTC. A busca usa a janela fixa `first_entry ± 3`, extraída do inventário anterior, sem consultar desfechos. As consultas abaixo são consultas efetivamente feitas; resultado vazio significa apenas que nenhum cue elegível foi recuperado nessas consultas.','',f'- Inventário: `{relative(INVENTORY)}`; SHA-256 `{m["inventory_sha256"]}`.',f'- Sementes de fontes: `{relative(SEED)}`; SHA-256 `{m["seed_sha256"]}`.',f'- Consultas dirigidas: `{relative(DISCOVERY)}`; SHA-256 `{m["discovery_queries_sha256"]}`.',f'- Capturas e decisões de `robots.txt`: `{relative(mp)}`.',f'- Manifesto da reauditoria: `{relative(rp)}`.',f'- Manifestos de consultas: `{relative(mp.parent / "query_manifest.json")}` e `{relative(rp.parent / "query_manifest.json")}`.',f'- Checksums dos arquivos preservados: `{relative(mp.parent / "checksums.sha256")}` e `{relative(rp.parent / "checksums.sha256")}`.','','O coletor consulta `robots.txt`, para em bloqueios, limita redirecionamentos a HTTPS e espera entre requisições ao mesmo host. Uma página de erro ou desafio não vira evidência. Os raws anteriores foram copiados em novos caminhos e conferidos por SHA-256. Para linhas `reevaluated_from`, `accessed_at` no CSV de evidências conserva o acesso online original; o manifesto registra `original_accessed_at` e o horário da cópia em `accessed_at`. A busca web para descobrir fontes não é raw e nunca basta para contar.','', '## Cobertura por país','','| País | Janela | Fontes contadas | Primeiro cue | Consultas registradas |','|---|---:|---:|---|---:|']
    for r in country:
        iso=r['iso3c']; n=sum(e['iso3c']==iso and e['counts_under_metric_rule']=='yes' for e in ev)
        lines.append(f'| {iso} | {r["search_windows_tried"]} | {n} | {r["first_cue_date"] or "não localizado"} | {r["n_queries_logged"]} |')
    lines+=['','## Consultas de descoberta e anos anteriores ao primeiro cue','','As consultas dirigidas abaixo se somam às consultas vinculadas a cada fonte no CSV de evidências e no manifesto JSON. A coluna de anos identifica a faixa buscada, não cobertura exaustiva de todos os veículos.','','| País | Anos | Consulta literal | Observação |','|---|---|---|---|']
    for r in q:
        lines.append(f'| {r["iso3c"]} | {r["years_targeted"]} | `{r["query_exact"].replace("|","/")}` | {r["observed_result"].replace("|","/")} |')
    lines+=['','## Fontes: captura, decisão e proveniência','','`reused_hash_verified` no terminal significa que o raw foi preservado em uma captura anterior e seu SHA-256 foi conferido; o status abaixo é o da captura original. Uma fonte `não` pode ser útil como contraste, confirmação anual ou pista bloqueada.','','| País | Fonte/data | URL | Captura | Raw e SHA-256 | Conta? | Razão |','|---|---|---|---|---|---|---|']
    for e in ev:
        c=cap[e['source_id']]
        raw=f'`{c["raw_file"]}`<br>`{c["sha256"]}`' if c.get('raw_file') else 'não arquivado'
        reason=e['metric_rule_reason'].replace('|','/').replace('\n',' ')
        lines.append(f'| {e["iso3c"]} | `{e["source_id"]}` ({e["publication_date"]}) | [origem]({e["url"]}) | `{c["status"]}` | {raw} | {e["counts_under_metric_rule"]} | {reason} |')
    seed={r['source_id']:r for r in read_csv(REAUDIT_SEED)}
    lines+=['','## Reauditoria de sete países: capturas','','| País | Fonte | Papel | Captura | Raw e SHA-256 |','|---|---|---|---|---|']
    for c in rm['sources']:
        s=seed[c['source_id']];raw=f'`{c["raw_file"]}`<br>`{c["sha256"]}`' if c.get('raw_file') else 'não arquivado'
        lines.append(f'| {c["iso3c"]} | [`{c["source_id"]}`]({c["url"]}) | {s["role"]} | `{c["status"]}` | {raw} |')
    lines+=['','## Limite inferencial','','A data encontrada é a primeira entre as fontes elegíveis recuperadas e arquivadas nesta busca. A ausência de resultado anterior não demonstra ausência de cobertura histórica. `low` exigiria imprensa nacional e fonte oficial verificadas em toda a janela, além de cobertura comercial contemporânea sem rótulo; não há país que cumpra esse limiar aqui.','']
    (REPORT/'targeted_collection_log.md').write_text('\n'.join(lines),encoding='utf-8')

def build() -> None:
    inv = inventory()
    items = candidates() + legacy_candidates()
    manifest = latest()
    if manifest['seed_sha256'] != sha(SEED) or manifest['inventory_sha256'] != sha(INVENTORY) or manifest['discovery_queries_sha256'] != sha(DISCOVERY):
        raise ValueError('Capture inputs changed; rerun collect')
    captures = {r['source_id']:r for r in manifest['sources']}
    if set(captures) != {r['source_id'] for r in items}:
        raise ValueError('Manifest and source seed differ')
    old_fields = list(read_csv(OLD_FILES[1])[0])
    extras = ['source_id','publisher_family','entity_in_source','period_in_source','annual_confirmation_source_id','counts_under_metric_rule','metric_rule_reason','reevaluated_from']
    evidence = []
    for r in items:
        cap = captures[r['source_id']]
        raw = ROOT / cap['raw_file'] if cap.get('raw_file') else None
        raw_ok = bool(raw and raw.is_file() and sha(raw) == cap.get('sha256') and cap['status'] in {'ok','copied_legacy'} and raw.stat().st_size > 500)
        if raw_ok and raw:
            preview = raw_text(raw)[:5000].lower()
            if len(preview.strip()) < 200 or any(s in preview for s in ['just a moment...', 'access denied', 'error 403', 'http error 404']):
                raw_ok = False
        # A source is counted only after a valid, hash-matching capture exists.
        count = r['planned_count'] == 'yes' and raw_ok
        row = {k:'' for k in old_fields+extras}
        row.update(r)
        row.update(iso3c=r['iso3c'],country_name=inv[r['iso3c']]['country_name'],entry_year=inv[r['iso3c']]['first_entry'],evidence_year=r['publication_date'][:4],source_country=r.get('source_country') or inv[r['iso3c']]['country_name'],raw_file=cap.get('raw_file',''),accessed_at=cap.get('original_accessed_at') or cap['accessed_at'],counts_under_metric_rule='yes' if count else 'no',metric_rule_reason=r['metric_rule_reason'] if raw_ok else r['metric_rule_reason']+' Capture unavailable/invalid: '+str(cap['status']))
        if r.get('planned_count') == 'yes' and not r.get('reevaluated_from'):
            row['rank_label_english'] = ENGLISH_LABELS.get(r['source_id'],'')
            row['excerpt_under_25_words'] = r.get('rank_label_original','') if len(r.get('rank_label_original','').split()) < 25 else ''
            row['label_type'] = 'export_rank' if r['metric_in_source'] in {'goods_exports','goods_services_exports','services_exports'} else 'generic_trade_partner'
            row['explicit_rank_language'] = 'true'
        if not count: row['evidence_strength']='DO_NOT_COUNT'
        row['search_window']=f"{int(inv[r['iso3c']]['first_entry'])-3}-{int(inv[r['iso3c']]['first_entry'])+3}"
        evidence.append(row)
    evidence.sort(key=lambda r:(ISO.index(r['iso3c']),r['publication_date'],r['source_id']))
    write_csv(DATA/'status_cue_source_evidence_targeted.csv',old_fields+extras,evidence)
    previous = {r['iso3c']:r for path in COUNTRY_OLD for r in read_csv(path) if r['iso3c'] in ISO}
    old_country_fields = list(read_csv(COUNTRY_OLD[1])[0])
    country_extras = ['previous_code','first_cue_date','first_cue_date_precision','first_cue_source_id','first_cue_metric','first_cue_period','annual_confirmation_source_id','metrics_in_public_use','metric_conflicts','years_searched_before_first_cue']
    countries = []
    for iso in ISO:
        rows = [r for r in evidence if r['iso3c']==iso]
        counted = [r for r in rows if r['counts_under_metric_rule']=='yes']
        first = min(counted,key=lambda r:r['publication_date']) if counted else {}
        families = {r['publisher_family'] for r in counted}
        code = 'high' if len(families)>=2 else 'medium' if counted else 'unknown'
        prior = previous[iso]
        row = {**prior,**{k:'' for k in country_extras}}
        row.update(previous_code=prior['salience_code'],salience_code=code,negative_case_candidate='no',n_newspaper_sources_strong=str(sum(r['source_type'] in {'newspaper','local_news','national_news_agency','business_news'} for r in counted)),n_official_sources_strong=str(sum(r['source_type'].startswith('official') for r in counted)),n_total_strong_or_moderate=str(len(counted)),has_explicit_export_rank_label=str(any(r['metric_in_source']=='goods_exports' for r in counted)).lower(),has_explicit_generic_trade_partner_label=str(any(r['metric_in_source']!='goods_exports' for r in counted)).lower(),has_official_uptake=str(any(r['source_type'].startswith('official') for r in counted)).lower(),has_newspaper_uptake=str(any(r['source_type'] in {'newspaper','local_news','national_news_agency','business_news'} for r in counted)).lower(),first_cue_date=first.get('publication_date',''),first_cue_date_precision=('day' if len(first.get('publication_date',''))==10 else 'month' if len(first.get('publication_date',''))==7 else 'year' if first else ''),first_cue_source_id=first.get('source_id',''),first_cue_metric=first.get('metric_in_source',''),first_cue_period=first.get('period_in_source',''),annual_confirmation_source_id=first.get('annual_confirmation_source_id',''),metrics_in_public_use=';'.join(sorted({r['metric_in_source'] for r in rows if r['metric_in_source']!='unspecified'})),search_windows_tried=f"{int(inv[iso]['first_entry'])-3}-{int(inv[iso]['first_entry'])+3}",years_searched_before_first_cue=f"{int(inv[iso]['first_entry'])-3}-{int(first['publication_date'][:4])-1}" if first and int(first['publication_date'][:4])>int(inv[iso]['first_entry'])-3 else '',n_queries_logged=str(sum(bool(r['query_used']) for r in rows)+sum(r['iso3c']==iso for r in read_csv(DISCOVERY))))
        row['metric_conflicts'] = METRIC_CONFLICTS.get(iso,'')
        row['remaining_gaps'] = REMAINING_GAPS.get(iso,'')
        row['coding_rationale'] = f"{len(counted)} archived countable source(s), {len(families)} publisher family/families; earliest {first.get('source_id','none')}."
        countries.append(row)
    write_csv(DATA/'status_cue_country_codes_targeted.csv',old_country_fields+country_extras,countries)

ENGLISH_LABELS = {
 'jpn_jcast_2007_04_26':'China excluding Hong Kong became Japan largest trading partner',
 'jpn_japantimes_2007_05_13':'China excluding Hong Kong was Japan top trading partner',
 'mys_miti_2010_02_22':'China is now Malaysia largest trading partner',
 'mys_miti_2009_report':'The PRC surpassed Singapore as Malaysia largest trading partner in 2009',
 'mys_bnm_2010_04_28':'China now becoming Malaysia largest trading partner',
 'per_andina_2011_05_16':'China is the main destination of Peruvian exports',
 'per_andina_2012_02_07':'China led destinations of Peruvian exports in 2011',
 'per_andina_2011_10_22':'China is Peru main trading partner',
 'sau_alriyadh_2013_02_12':'China became Saudi Arabia largest trading partner',
 'sau_alwatan_2013_02_27':'China became Saudi Arabia first trading partner',
 'rus_bfm_2011_01_14':'China became Russia largest trading partner',
 'rus_km_2011_06_16':'China overtook Germany to become Russia first trading partner',
 'rus_vedomosti_2014_02_12':'China became Russia largest trading partner in 2013',
 'mmr_irrawaddy_2012_04_04':'China is Burma largest trading partner',
 'mmr_irrawaddy_2012_11_20':'China is Burma largest trading partner',
 'mmr_dvb_2014_05_09':'China still Burma top trading partner',
 'tkm_gov_2011_11_23':'China is now Turkmenistan largest foreign-trade partner',
 'tkm_gov_2012_06_07':'China ranks first in Turkmenistan total foreign trade',
}

METRIC_CONFLICTS = {
 'JPN':'FY2006 mainland-only two-way goods China first; final 2008 goods exports United States first. Earlier MOFA/Japan Times export formulations aggregate mainland China with Hong Kong.',
 'MYS':'2009 annual two-way goods China first; January-October 2009 partial reporting had China second; Hong Kong-inclusive export claims excluded.',
 'PER':'2010 annual goods exports United States first; 2011 current goods exports China first. October 2011 total-trade wording and earlier prospective total-trade claim use another metric.',
 'SAU':'Al Watan in February 2013 reports China first in 2012 two-way goods trade based on the Chinese ambassador; Al Eqtisadiah in March 2014 cites Saudi GASTAT figures putting China second after the United States for 2012 in the same metric. The cue documents press language, not a reconciled statistical rank. In 2013 annual goods exports China was second in Al Riyadh/SPA.',
 'RUS':'2009 first-quarter two-way China first but full 2009 Netherlands/Germany ahead; 2010 January-November cue is confirmed for full 2010 by the Putin quote in KM.ru. Vedomosti annual ordering alone covers non-CIS partners.',
 'KAZ':'2009 ministerial ordering puts China before Russia and Italy, but 2009 official bilateral sums put Russia ahead; the wording does not explicitly declare China first.',
 'AGO':'Web-indexed 2008 INE annual says China first in total goods exports, but its mirror could not be archived; BNI claim concerns mineral exports only.',
 'MMR':'FY2013-14 two-way goods China first in DVB; 2013 Irrawaddy commentary puts Thailand first for an unspecified earlier period.',
 'SLB':'A later retrospective says China overtook Japan in 2003, but 2004 CBSI report identifies Japan as first. No eligible contemporaneous archived cue in the window.',
 'TKM':'A November 23 2011 official current-status statement says China is Turkmenistan largest foreign-trade partner. A separate November 24 statement explicitly limits a similar rank to Jan-Sep 2011 and is not counted without full-year confirmation. Full 2010 China fourth.'
}

REMAINING_GAPS = {
 'JPN':'No earlier mainland-only local rank claim recovered for 2005-2006.',
 'MYS':'Earlier local full-year China-first article before February 2010 not recovered.',
 'PER':'No earlier current China-first label recovered; 2009-2010 official exports put United States first.',
 'SAU':'Earlier Al Riyadh February 12 2013 page blocked by robots; December 2012 Al Madina refers to 2011 and has uncertain editorial provenance.',
 'PHL':'PSA direct capture blocked; accessible rankings put other countries first and a GMA China-first claim is semiconductor-only.',
 'RUS':'2009 first-quarter cue lacks matching full-year confirmation.',
 'KAZ':'Official 2009 statistics and ministerial listing conflict; no unambiguous local China-first rank claim within 2004-2010.',
 'AGO':'INE 2008 annual is indexed on a third-party mirror but HTTP 403 prevents raw capture; its date is only June 2009. The official INE index lists 2008 foreign-trade bulletins, but historical detail pages timed out; earlier newsroom archives largely unavailable.',
 'COD':'Central-bank PDF direct capture fails; available text does not establish the rank for all exports.',
 'MRT':'AMI archives checked; available 2006-2007 cooperation coverage lacks a countrywide first rank.',
 'MMR':'Earlier 2012 Irrawaddy pages blocked (HTTP 403); FY2013-14 DVB article archived.',
 'SLB':'CBSI 2004 source not directly captured (HTTP 404); historical Solomon Star/SIBC archives not recovered.',
 'SLE':'Original Awoko page unavailable; third-party copy attributes China-first language to Chinese economic counsellor.',
 'ERI':'Shabait coverage of cooperation recovered but no verified China-first rank within 2011-2017.',
 'TKM':'No earlier local first-partner cue recovered; the separate Jan-Sep 2011 rank lacks annual same-metric confirmation. Current-status official releases from November 2011 and June 2012 archived.'
}

def validate() -> None:
    manifest = latest()
    if manifest['seed_sha256'] != sha(SEED) or manifest['inventory_sha256'] != sha(INVENTORY) or manifest['discovery_queries_sha256'] != sha(DISCOVERY):
        raise ValueError('Capture inputs changed; rerun collect')
    for r in manifest['sources']:
        if r.get('raw_file') and sha(ROOT/r['raw_file'])!=r['sha256']:
            raise ValueError('Raw hash mismatch: '+r['source_id'])
    e = read_csv(DATA/'status_cue_source_evidence_targeted.csv')
    c = read_csv(DATA/'status_cue_country_codes_targeted.csv')
    assert len(c)==15 and set(r['iso3c'] for r in c)==set(ISO)
    assert len(e)==len(candidates())+len(legacy_candidates())
    assert all(r['counts_under_metric_rule']=='no' or r['entity_in_source']=='mainland_china' for r in e)
    assert all(r['counts_under_metric_rule']=='no' or r['evidence_strength'] in {'strong','moderate'} for r in e)
    assert all(r['counts_under_metric_rule']=='no' or r['period_in_source'] not in {'month','quarter','semester'} or r['annual_confirmation_source_id'] for r in e)
    by_id = {r['source_id']:r for r in e}
    for r in e:
        if r['counts_under_metric_rule'] != 'yes':
            continue
        label = r['excerpt_under_25_words'] or r['rank_label_original']
        if not label or len(label.split()) >= 25:
            raise ValueError('Missing/long quoted rank label: '+r['source_id'])
        source_text = re.sub(r'\s+', ' ', raw_text(ROOT/r['raw_file']))
        if re.sub(r'\s+', ' ', label) not in source_text:
            raise ValueError('Rank label does not occur in archived raw: '+r['source_id'])
        confirmation_id = r['annual_confirmation_source_id']
        if confirmation_id:
            conf = by_id[confirmation_id]
            if conf['iso3c'] != r['iso3c'] or conf['metric_in_source'] != r['metric_in_source'] or conf['period_in_source'] not in {'annual','fiscal_year'} or not conf['raw_file']:
                raise ValueError('Invalid annual confirmation: '+r['source_id'])
    assert all(r['negative_case_candidate']=='no' or r['salience_code']=='low' for r in c)
    rr = read_csv(DATA/'status_cue_subannual_reaudit_2026.csv')
    assert len(rr)==7 and set(r['iso3c'] for r in rr)==set(REAUDIT_DECISIONS)
    for r in rr:
        assert sha(ROOT/r['first_cue_raw_file'])==r['first_cue_sha256']
        if r['annual_confirmation_source_id']:
            assert sha(ROOT/r['annual_confirmation_raw_file'])==r['annual_confirmation_sha256']
    print('PASS: 15 countries, legacy coverage, raw hashes, entity, subannual and negative-case invariants')

if __name__ == '__main__':
    p=argparse.ArgumentParser()
    p.add_argument('command',choices=['collect','build','validate','reaudit_collect','reaud_build','collection_log'])
    args=p.parse_args()
    if args.command=='collect': print(capture())
    elif args.command=='build': build()
    elif args.command=='reaudit_collect': print(reaud_capture())
    elif args.command=='reaud_build': reaud_build()
    elif args.command=='collection_log': collection_log()
    else: validate()
