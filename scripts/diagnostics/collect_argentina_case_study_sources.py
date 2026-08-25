#!/usr/bin/env python3
"""Preserve sources for the Argentina/status-salience donor case studies.

The source register is deliberately separate from the targets pipeline.  It
downloads immutable raw snapshots when the publisher permits access, records
failed access without converting it into evidence of absence, and writes the
source-level CSV used by the 2026-08-25 diagnostic report.

No paid API, account, cookie, or credential is used.
"""

from __future__ import annotations

import csv
import hashlib
import json
import re
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
RAW_DIR = ROOT / "data" / "raw" / "argentina_case_study"
REPORT_DIR = ROOT / "quality_reports" / "argentina_case_study"
SOURCE_CSV = REPORT_DIR / "2026-08-25_status_salience_sources.csv"
SEARCH_LOG_CSV = REPORT_DIR / "2026-08-25_status_salience_search_log.csv"
CHECKSUMS = RAW_DIR / "checksums.sha256"
ACCESSED_AT = datetime.now(timezone.utc).replace(microsecond=0).isoformat()
USER_AGENT = (
    "RDD-Trade Argentina case-study collector/1.0 "
    "(academic reproducibility; no paid APIs)"
)


@dataclass(frozen=True)
class Source:
    source_id: str
    country: str
    iso3c: str
    donor_pool: str
    donor_weight: str
    rank_in_project: str
    rank_year: str
    vehicle: str
    source_type: str
    source_country: str
    publication_date: str
    url: str
    title: str
    language: str
    window: str
    query_used: str
    rank_label_original: str
    rank_level: str
    explicit_rank_language: str
    volume_language: str
    official_uptake: str
    local_or_official: str
    method_eligible: str
    evidence_strength: str
    case_role: str
    notes: str


def s(*values: str) -> Source:
    return Source(*values)


SOURCES = [
    s(
        "arg_ambito_2007", "Argentina", "ARG", "Latin America", "0.059",
        "2", "2007", "Ámbito", "business_news", "Argentina", "2007-12-20",
        "https://www.ambito.com/secciones-especiales/el-comercio-china-n3477301",
        "El comercio con China", "es", "principal: 2007--2008",
        'site:ambito.com Argentina China "segundo destino" exportaciones 2007',
        "el segundo destino de las exportaciones argentinas", "export_destination_2",
        "yes", "yes", "no", "yes", "yes", "strong", "Argentina core",
        "Contemporary domestic business press; the result-level snippet contains the rank phrase.",
    ),
    s(
        "arg_lanacion_2008", "Argentina", "ARG", "Latin America", "0.059",
        "2", "2007", "La Nación", "newspaper", "Argentina", "2008-01-16",
        "https://www.lanacion.com.ar/economia/las-exportaciones-superaron-los-us-55000-millones-en-2007-nid979301/",
        "Las exportaciones superaron los US$ 55.000 millones en 2007", "es",
        "principal: 2007--2008",
        'site:lanacion.com.ar exportaciones 2007 Brasil China Estados Unidos orden',
        "Brasil, China y Estados Unidos, en ese orden", "ordered_export_destinations",
        "yes", "yes", "no", "yes", "yes", "strong", "Argentina core",
        "Contemporary domestic press reporting official customs data.",
    ),
    s(
        "arg_pagina12_2008", "Argentina", "ARG", "Latin America", "0.059",
        "2", "2007", "Página/12 Cash", "newspaper", "Argentina", "2008-04-27",
        "https://www.pagina12.com.ar/diario/suplementos/cash/17-3470-2008-04-27.html",
        "Un socio estratégico", "es", "principal: 2007--2008",
        'site:pagina12.com.ar China "segundo socio comercial" 2007 Argentina',
        "China fue el segundo socio comercial del país en 2007", "generic_trade_partner_2",
        "yes", "yes", "no", "yes", "yes", "moderate", "Argentina supplement",
        "Generic bilateral-trade rank, not the exact export-destination construct.",
    ),
    s(
        "arg_cancilleria_2009a", "Argentina", "ARG", "Latin America", "0.059",
        "2", "2007", "Cancillería Argentina", "official_speech", "Argentina", "2009-09-07",
        "https://cancilleria.gob.ar/es/actualidad/comunicados/desde-beijing-taiana-califica-las-relaciones-entre-argentina-y-china-como",
        "Desde Beijing, Taiana califica las relaciones ... como estratégicas", "es",
        "supplemental official uptake",
        'site:cancilleria.gob.ar "segundo destino" exportaciones argentinas China',
        "China se transformó en el segundo destino", "export_destination_2",
        "yes", "yes", "yes", "yes", "no", "strong", "Argentina official uptake",
        "Outside the strict 2007--2008 window; relevant as subsequent official uptake.",
    ),
    s(
        "arg_cancilleria_2009b", "Argentina", "ARG", "Latin America", "0.059",
        "2", "2007", "Cancillería Argentina", "government_news", "Argentina", "2009-10-16",
        "https://cancilleria.gob.ar/es/actualidad/comunicados/argentina-china-reunion-economica-de-alto-nivel",
        "Argentina-China: reunión económica de alto nivel", "es",
        "supplemental official uptake",
        'site:cancilleria.gob.ar Argentina China "segundo destino" 2009',
        "el segundo destino de las exportaciones argentinas", "export_destination_2",
        "yes", "yes", "yes", "yes", "no", "strong", "Argentina official uptake",
        "Links export volume and status to the bilateral high-level commission.",
    ),
    s(
        "arg_ambito_2010", "Argentina", "ARG", "Latin America", "0.059",
        "2", "2010", "Ámbito", "business_news", "Argentina", "2010-07-09",
        "https://www.ambito.com/edicion-impresa/cristina-viaja-china-la-soja-la-agenda-n3631410",
        "Cristina viaja a China con la soja en la agenda", "es",
        "secondary: 2010--2011",
        'site:ambito.com Cristina China 2010 "segundo destino" exportaciones',
        "segundo destino de las exportaciones argentinas", "export_destination_2",
        "yes", "yes", "no", "yes", "yes", "strong", "Argentina secondary",
        "Domestic coverage connects the rank to a presidential visit and business mission.",
    ),
    s(
        "arg_cancilleria_2007_volume", "Argentina", "ARG", "Latin America", "0.059",
        "3", "2007-H1", "Cancillería Argentina", "government_news", "Argentina", "2007",
        "https://cancilleria.gob.ar/es/actualidad/comunicados/nuevos-logros-en-la-relacion-comercial-con-china",
        "Nuevos logros en la relación comercial con China", "es",
        "principal: 2007--2008",
        'site:cancilleria.gob.ar China tercer cliente exportaciones primer semestre 2007',
        "China fue el tercer cliente", "export_destination_3",
        "yes", "yes", "yes", "yes", "yes", "moderate", "Argentina timing check",
        "First-half rank shows that the move to second place occurred within 2007.",
    ),
    s(
        "arg_wits_2007", "Argentina", "ARG", "Latin America", "0.059",
        "2", "2007", "WITS/World Bank", "international_statistics", "International", "undated",
        "https://wits.worldbank.org/CountryProfile/es/Country/ARG/Year/2007/Summarytext",
        "Argentina Trade Summary 2007", "es", "retrospective rank audit",
        "WITS Argentina export partners 2007 China Chile United States",
        "Brazil, China, United States, Chile", "ordered_export_destinations",
        "yes", "yes", "no", "no", "no", "strong", "metric audit",
        "Not public-cue evidence; used only to audit the partner ordering and displacement claim.",
    ),
    s(
        "col_eltiempo_rank_2014", "Colombia", "COL", "Latin America", "0.068",
        "2", "2014", "El Tiempo", "newspaper", "Colombia", "2014-08-11",
        "https://www.eltiempo.com/archivo/documento/CMS-14368997",
        "China gana participación entre los destinos de exportación", "es",
        "principal: 2014--2015",
        'site:eltiempo.com exportaciones China 12,4 Panamá "le siguen" 2014',
        "Le siguen, en su orden, China ... Panamá", "ordered_export_destinations",
        "yes", "yes", "no", "yes", "yes", "strong", "rank-2 comparison",
        "Domestic newspaper gives an ordered list after the United States.",
    ),
    s(
        "col_eltiempo_half_2014", "Colombia", "COL", "Latin America", "0.068",
        "2", "2014", "El Tiempo", "newspaper", "Colombia", "2014-09-02",
        "https://www.eltiempo.com/archivo/documento/CMS-14475655",
        "Exportaciones a China ya son la mitad de las que van a EE. UU.", "es",
        "principal: 2014--2015",
        'site:eltiempo.com 2014 China exportaciones mitad Estados Unidos socio histórico',
        "mitad de las que van a Estados Unidos", "rank_comparison_not_ordinal",
        "no", "yes", "no", "yes", "yes", "moderate", "rank-2 comparison",
        "Status comparison is salient but the title itself does not say second.",
    ),
    s(
        "col_dane_2014", "Colombia", "COL", "Latin America", "0.068",
        "2", "2014", "DANE", "official_statistics", "Colombia", "2014",
        "https://www.dane.gov.co/files/investigaciones/boletines/exportaciones/bol_exp_jul14.pdf",
        "Boletín técnico: exportaciones, julio de 2014", "es",
        "principal: 2014--2015",
        'site:dane.gov.co bol_exp_jul14 China 11,5 Estados Unidos 24,8',
        "Estados Unidos 24,8%; China 11,5%", "ordered_official_table",
        "yes", "yes", "yes", "yes", "yes", "strong", "rank-2 comparison",
        "Contemporary official table orders destinations by export share.",
    ),
    s(
        "col_elcolombiano_2015", "Colombia", "COL", "Latin America", "0.068",
        "2", "2014", "El Colombiano", "newspaper", "Colombia", "2015-02-18",
        "https://www.elcolombiano.com/amp/negocios/economia/exportaciones-colombianas-cayeron-6-8-por-ciento-en-2014-dane-ED1324116",
        "Exportaciones colombianas cayeron 6,8 por ciento en 2014", "es",
        "principal: 2014--2015",
        'site:elcolombiano.com "El segundo destino fue China" 2014',
        "El segundo destino fue China", "export_destination_2",
        "yes", "yes", "no", "yes", "yes", "strong", "rank-2 comparison",
        "Following-year domestic report of DANE's annual result.",
    ),
    s(
        "cri_ap_official_2007", "Costa Rica", "CRI", "Latin America", "0.052",
        "2", "2007", "Associated Press syndication", "news_agency", "United States", "2007-02-19",
        "https://www.myplainview.com/news/article/Resaltan-aumento-de-exportaciones-de-Costa-Rica-a-8549548.php",
        "Resaltan aumento de exportaciones de Costa Rica a China", "es",
        "principal: 2007--2008",
        'Costa Rica China segundo destino exportaciones 2007 ministro comercio',
        "China ... segundo destino de las exportaciones", "export_destination_2",
        "yes", "yes", "yes", "yes", "no", "strong", "rank-2 comparison",
        "Non-domestic syndication, but quotes a contemporary Costa Rican minister; supplemental.",
    ),
    s(
        "cri_procomer_2007", "Costa Rica", "CRI", "Latin America", "0.052",
        "2", "2007", "PROCOMER", "official_statistics", "Costa Rica", "2008",
        "https://www.procomer.com/wp-content/uploads/Materiales/anuario-estadistico-exportacion-20072020-01-02_16-02-55.pdf",
        "Anuario estadístico de exportación 2007", "es",
        "principal: 2007--2008",
        'site:procomer.com "segundo destino" China exportaciones 2007',
        "China, el segundo destino de las exportaciones costarricenses", "export_destination_2",
        "yes", "yes", "yes", "yes", "yes", "strong", "rank-2 comparison",
        "Domestic official export yearbook.",
    ),
    s(
        "cri_chamber_2007", "Costa Rica", "CRI", "Latin America", "0.052",
        "2", "2007", "Cámara de Industria y Comercio Costa Rica-China", "business_magazine", "Costa Rica", "2007",
        "https://www.cicccr.com/conexion/Conexion14.pdf",
        "Conexión China, número 14", "es", "principal: 2007--2008",
        'Costa Rica China "segundo mercado" exportaciones Conexion 14',
        "después de Estados Unidos ... el segundo mercado", "export_destination_2",
        "yes", "yes", "no", "yes", "yes", "moderate", "rank-2 comparison",
        "Domestic bilateral chamber publication; not independent press.",
    ),
    s(
        "cri_comex_current", "Costa Rica", "CRI", "Latin America", "0.052",
        "2", "2007", "COMEX Costa Rica", "government_background", "Costa Rica", "undated",
        "https://www.comex.go.cr/tratados/china/",
        "Tratado de Libre Comercio entre Costa Rica y China", "es",
        "retrospective official uptake",
        'site:comex.go.cr tratados China segundo socio comercio Costa Rica',
        "segundo socio comercial individual", "generic_trade_partner_2",
        "yes", "yes", "yes", "yes", "no", "moderate", "official uptake",
        "Current background page; supports institutional uptake, not contemporaneous coding.",
    ),
    s(
        "cri_uned_retrospective", "Costa Rica", "CRI", "Latin America", "0.052",
        "2", "2006--2008", "UNED Observatorio de Comercio Exterior", "public_university_analysis", "Costa Rica", "undated",
        "https://www.uned.ac.cr/ocex/index.php/publicaciones/revistas?catid=124&id=647%3Aabriendo-las-puertas-a-asia-10-anos-del-tlc-con-china&view=article",
        "TLC con China: geopolítica, comercio y diplomacia", "es",
        "retrospective mechanism audit",
        'site:uned.ac.cr China "segundo mercado de destino" exportaciones Costa Rica 2006',
        "segundo mercado de destino de nuestras exportaciones", "export_destination_2",
        "yes", "yes", "no", "yes", "no", "strong", "retrospective political uptake",
        "Costa Rican public-university analysis explicitly links the rank to the 2007 diplomatic switch; outside contemporaneous coding.",
    ),
    s(
        "ecu_flacso_2019", "Ecuador", "ECU", "Latin America", "0.040",
        "2", "2015", "FLACSO Ecuador repository", "academic_thesis", "Ecuador", "2019",
        "https://repositorio.flacsoandes.edu.ec/bitstream/10469/15641/8/TFLACSO-2019SLHV.pdf",
        "Relaciones comerciales Ecuador-China", "es", "retrospective metric audit",
        'Ecuador China sexto destino exportaciones 2015 FLACSO',
        "China ... sexto destino de exportaciones en 2015", "export_destination_6",
        "yes", "yes", "no", "yes", "no", "strong", "metric contradiction",
        "Later domestic academic source conflicts with the project rank-2 flag.",
    ),
    s(
        "ecu_planv_current", "Ecuador", "ECU", "Latin America", "0.040",
        "2", "2015", "Plan V", "digital_news", "Ecuador", "undated",
        "https://planv.com.ec/historias/radiografia-china-america-latina-y-el-ecuador-diez-anos-la-franja-y-la-ruta/",
        "Radiografía de China en América Latina y el Ecuador", "es",
        "retrospective metric audit",
        'site:planv.com.ec China Ecuador sexto destino exportaciones 2015',
        "en 2015, China ocupaba el sexto lugar", "export_destination_6",
        "yes", "yes", "no", "yes", "no", "strong", "metric contradiction",
        "Later domestic report says second place was reached only after the study period.",
    ),
    s(
        "jam_statin_historical", "Jamaica", "JAM", "Latin America", "0.052",
        "2", "2004", "STATIN Jamaica", "official_statistics", "Jamaica", "undated",
        "https://statinja.gov.jm/trade-econ%20statistics/internationalmerchandisetrade/traderankine.aspx",
        "Trade ranking by country", "en", "retrospective metric audit",
        'site:statinja.gov.jm 2004 domestic exports China rank Jamaica',
        "United States, Canada, China", "ordered_export_destinations",
        "yes", "yes", "yes", "yes", "no", "strong", "metric contradiction",
        "Historical official table appears to place China third in domestic exports.",
    ),
    s(
        "jam_embassy_2005", "Jamaica", "JAM", "Latin America", "0.052",
        "2", "2004", "Embassy of China in Jamaica", "foreign_government", "China", "2005",
        "https://jm.china-embassy.gov.cn/eng/zygx/jmhz/200509/t20050910_10326779.htm",
        "Trade cooperation between China and Jamaica", "en", "principal: 2004--2005",
        'China Jamaica trade volume 2004 biggest English Caribbean partner',
        "biggest English-speaking Caribbean trading partner", "different_construct_rank1",
        "yes", "yes", "yes", "no", "no", "weak", "volume-only comparator",
        "Foreign-government source and a different construct; not countable as domestic cue.",
    ),
    s(
        "ven_worldbank_2007", "Venezuela", "VEN", "Latin America", "0.026",
        "2", "2007", "World Bank", "international_statistics", "International", "2012",
        "https://documents1.worldbank.org/curated/en/970071468309390287/pdf/72796020090Ven0Box0371958B00PUBLIC0.pdf",
        "Venezuela trade profile", "en", "retrospective metric audit",
        'Venezuela export markets 2007 China 7 percent World Bank',
        "United States, Colombia, Brazil, China", "ordered_export_destinations",
        "yes", "yes", "no", "no", "no", "strong", "metric contradiction",
        "Later international profile places China fourth, not second.",
    ),
    s(
        "ven_elpais_2007", "Venezuela", "VEN", "Latin America", "0.026",
        "2", "2007", "El País", "newspaper", "Spain", "2007-11-07",
        "https://elpais.com/internacional/2007/11/07/actualidad/1194390012_850215.html",
        "Chávez estrecha lazos con China", "es", "principal: 2007--2008",
        'Venezuela China comercio petróleo 2007 Chávez visita',
        "", "none", "no", "yes", "yes", "no", "no", "moderate", "volume-only comparator",
        "Strong strategic/volume salience without matching export-rank language.",
    ),
    s(
        "mlt_economic_survey_2012", "Malta", "MLT", "Global", "0.03047",
        "goods: not 1; goods plus services: 1", "2011", "Government of Malta", "official_statistics", "Malta", "2012",
        "https://www.parlament.mt/media/87889/economic-survey-2012.pdf",
        "Economic Survey, November 2012", "en", "following year: 2011--2012",
        'site:parlament.mt economic survey 2012 Malta exports China Hong Kong 2011',
        "Germany 326.2; Hong Kong 286.1; China 71.5", "ordered_export_values",
        "yes", "yes", "yes", "yes", "yes", "strong", "sector-definition correction",
        "Confirms the author-identified sector-definition error: China was not first in goods; the first-place result applies only after services are included.",
    ),
    s(
        "mlt_enterprise_2012", "Malta", "MLT", "Global", "0.03047",
        "goods: not 1; goods plus services: 1", "2011", "Malta Enterprise", "government_news", "Malta", "2012",
        "https://www.maltaenterprise.com/business-delegation-visit-hong-kong-shanghai",
        "Business delegation to visit Hong Kong and Shanghai", "en",
        "following year: 2011--2012",
        'site:maltaenterprise.com China 71.6 Hong Kong 286 exports 2011',
        "China €71.6m; Hong Kong €286m", "separate_export_values",
        "yes", "yes", "yes", "yes", "yes", "strong", "sector-definition correction",
        "Domestic official page corroborates that China was not the first goods destination.",
    ),
    s(
        "sgp_mti_ess_2005", "Singapore", "SGP", "Global candidate", "not in stale on-disk weights",
        "goods exports: 2; goods and services two-way: 2", "2005", "Ministry of Trade and Industry", "official_report", "Singapore", "2006",
        "https://isomer-user-content.by.gov.sg/166/15a8565c-c494-4f59-9750-ef682807e18e/ess_2005ann_full-report.pdf",
        "Economic Survey of Singapore 2005", "en", "principal: 2005--2006",
        'site:mti.gov.sg Economic Survey Singapore 2005 China export market rank',
        "China was Singapore's 4th largest trading partner", "total_merchandise_trade_4",
        "yes", "yes", "yes", "yes", "yes", "strong", "Singapore 2005 metric audit",
        "Contemporary domestic report does not reproduce or publicize the ITPD-E goods-export rank 2; it uses total merchandise trade and calls China fourth.",
    ),
    s(
        "sgp_mfa_yeo_2005", "Singapore", "SGP", "Global candidate", "not in stale on-disk weights",
        "goods exports: 2; goods and services two-way: 2", "2005", "Ministry of Foreign Affairs", "official_speech", "Singapore", "2005-12-29",
        "https://www.mfa.gov.sg/newsroom/press-statements-transcripts-and-photos/speech-by-george-yeo-minister-for-foreign-affairs-at-the-35th-anniversary-dinner-of-the-sporechina-b-29-dec-2005/",
        "Speech at the 35th Anniversary Dinner of the Singapore-China Business Association", "en",
        "principal: 2005--2006",
        'site:mfa.gov.sg Singapore China Business Association 29 December 2005 bilateral trade',
        "", "none", "no", "yes", "yes", "yes", "yes", "moderate", "Singapore 2005 volume and strategy",
        "The foreign minister stresses record bilateral trade, investment, ASEAN integration and strategic interest, but no Singapore export-rank cue.",
    ),
    s(
        "sgp_mti_fta_2006", "Singapore", "SGP", "Global candidate", "not in stale on-disk weights",
        "goods exports: 2; goods and services two-way: 2", "2005", "Ministry of Trade and Industry", "government_news", "Singapore", "2006-08-25",
        "https://www.mti.gov.sg/newsroom/china-and-singapore-to-launch-fta-negotiations/",
        "China and Singapore to launch FTA negotiations", "en", "principal: 2005--2006",
        'site:mti.gov.sg China Singapore launch FTA negotiations 2005 fourth largest trading partner',
        "China is now Singapore's 4th largest trading partner", "total_merchandise_trade_4",
        "yes", "yes", "yes", "yes", "yes", "strong", "Singapore 2005 official uptake",
        "Official policy action is linked to record trade and investment, not to China being the second goods-export destination in ITPD-E.",
    ),
    s(
        "sgp_mti_sip_2013", "Singapore", "SGP", "Global candidate", "not in stale on-disk weights",
        "goods exports: 2; goods and services two-way: 1", "2013", "Ministry of Trade and Industry", "government_news", "Singapore", "2013-10-22",
        "https://www.nas.gov.sg/archivesonline/data/data/pdfdoc/20131029003/15th_sip_jsc_press_release.pdf",
        "Singapore and China announce new areas of cooperation at the 15th Suzhou Industrial Park Joint Steering Council", "en",
        "transition context: 2013",
        'site:nas.gov.sg Singapore China services export destination 2011 fifth 2013 SIP',
        "5th largest services export destination in 2011", "services_export_destination_5",
        "yes", "yes", "yes", "yes", "yes", "strong", "Singapore 2013 pre-result context",
        "Before the 2013 annual result, official language marked China as an important but not leading services destination.",
    ),
    s(
        "sgp_ie_review_2013", "Singapore", "SGP", "Global candidate", "not in stale on-disk weights",
        "goods exports: 2; goods and services two-way: 1", "2013", "International Enterprise Singapore", "official_statistics", "Singapore", "2014-02-20",
        "https://www.nas.gov.sg/archivesonline/data/data/pdfdoc/20140227003/mr00514_review_of_2013_trade_performance_2014_02_20.pdf",
        "Review of 2013 trade performance", "en", "principal: 2013--2014",
        'site:nas.gov.sg Review of 2013 trade performance China top trading partner Singapore',
        "Top trading partner: China; top NODX market: China", "total_merchandise_trade_1_and_nodx_1",
        "yes", "yes", "yes", "yes", "yes", "strong", "Singapore 2013 rank-1 cue",
        "Official annual tables put China first in total merchandise trade and non-oil domestic exports; these public constructs differ from all-goods export destination.",
    ),
    s(
        "sgp_mfa_uptake_2017", "Singapore", "SGP", "Global candidate", "not in stale on-disk weights",
        "goods exports: 2; goods and services two-way: 1", "2013", "Ministry of Foreign Affairs", "official_speech", "Singapore", "2017-03-02",
        "https://www.mfa.gov.sg/newsroom/press-statements-transcripts-and-photos/mfa-press-release-speeches-by-minister-for-foreign-affairs-dr-vivian-balakrishnan-senior-minister-of-02-mar-2017/",
        "Speeches during the Committee of Supply Debate", "en", "supplemental official uptake",
        'site:mfa.gov.sg since 2013 China Singapore largest trading partner parliament',
        "China is Singapore's largest trading partner, also since 2013", "generic_trading_partner_1",
        "yes", "yes", "yes", "yes", "no", "strong", "Singapore official uptake",
        "Later parliamentary speech embeds the 2013 first-place milestone in a broader bilateral and foreign-policy narrative.",
    ),
    s(
        "tcd_unctad_2005", "Chad", "TCD", "Global", "0.02769",
        "2", "2004", "UNCTAD", "international_report", "International", "2005",
        "https://unctad.org/system/files/official-document/ldcmisc20053_fr.pdf",
        "Profil de la vulnérabilité commerciale du Tchad", "fr",
        "following year: 2004--2005",
        'Tchad Chine destination exportations 2004 deuxième UNCTAD',
        "la Chine ... 21 pour cent des exportations", "export_share_no_ordinal",
        "no", "yes", "no", "no", "no", "moderate", "archive-limited case",
        "Confirms large China exposure, but not a domestic contemporaneous rank cue.",
    ),
    s(
        "geo_civil_2004", "Georgia", "GEO", "Global", "0.03048",
        "9", "2004", "Civil Georgia", "digital_news", "Georgia", "2004-12-26",
        "https://civil.ge/archives/106895",
        "Georgia, China boost relations", "en", "benchmark year: 2004--2005",
        'site:civil.ge China Georgia trade relations 2004 exports',
        "", "none", "no", "yes", "yes", "yes", "yes", "moderate", "non-top benchmark",
        "Local coverage calls 2004 a bilateral milestone but contains no export-rank cue.",
    ),
    s(
        "geo_wits_2004", "Georgia", "GEO", "Global", "0.03048",
        "9", "2004", "WITS/World Bank", "international_statistics", "International", "undated",
        "https://wits.worldbank.org/CountryProfile/en/Country/GEO/Year/2004/Summarytext",
        "Georgia Trade Summary 2004", "en", "retrospective rank audit",
        'WITS Georgia export partners 2004 China',
        "Turkey, Turkmenistan, Russia, Armenia, United Kingdom", "ordered_export_destinations",
        "yes", "yes", "no", "no", "no", "strong", "non-top benchmark",
        "Metric audit confirms that China was outside the leading export destinations.",
    ),
    s(
        "gtm_trade_office_2005", "Guatemala", "GTM", "Global", "0.02731",
        "10", "2005", "Associated Press syndication", "news_agency", "United States", "2005-06-12",
        "https://www.myplainview.com/news/article/Guatemala-abrir-oficinas-comerciales-en-Beijin-8703297.php",
        "Guatemala abrirá oficinas comerciales en Beijing", "es",
        "benchmark year: 2005--2006",
        'Guatemala oficinas comerciales Beijing 2005 exportó 20 millones importó 251',
        "exportó apenas 20 millones; importó 251 millones", "trade_values_no_ordinal",
        "no", "yes", "yes", "no", "no", "moderate", "non-top benchmark",
        "China was politically visible as an import relationship, without export-status language.",
    ),
    s(
        "gtm_wits_2005", "Guatemala", "GTM", "Global", "0.02731",
        "10", "2005", "WITS/World Bank", "international_statistics", "International", "undated",
        "https://wits.worldbank.org/CountryProfile/en/Country/GTM/Year/2005/TradeFlow/EXPIMP/Partner/by-country",
        "Guatemala trade by partner 2005", "en", "retrospective rank audit",
        'WITS Guatemala exports partners 2005 China',
        "United States, El Salvador, Honduras, Mexico, Nicaragua", "ordered_export_destinations",
        "yes", "yes", "no", "no", "no", "strong", "non-top benchmark",
        "China was a major import origin, not a top export destination.",
    ),
    s(
        "pry_lmt_2005", "Paraguay", "PRY", "Global", "0.02690",
        "11", "2005", "Associated Press syndication", "news_agency", "United States", "2005-01-23",
        "https://www.lmtonline.com/lmtenespanol/article/Paraguay-no-tendr-relaciones-diplom-ticas-con-10261960.php",
        "Paraguay no tendrá relaciones diplomáticas con China", "es",
        "benchmark year: 2005--2006",
        'Paraguay China relaciones diplomáticas 2005 exportaciones 7,6 importaciones 180',
        "exportaciones 7,6 millones; importaciones 180 millones", "trade_values_no_ordinal",
        "no", "yes", "yes", "no", "no", "moderate", "non-top benchmark",
        "Contemporary foreign-minister statement makes China salient diplomatically, not as export status.",
    ),
    s(
        "pry_wits_2005", "Paraguay", "PRY", "Global", "0.02690",
        "11", "2005", "WITS/World Bank", "international_statistics", "International", "undated",
        "https://wits.worldbank.org/CountryProfile/es/Country/PRY/Year/2005/Summarytext",
        "Paraguay Trade Summary 2005", "es", "retrospective rank audit",
        'WITS Paraguay export partners 2005 China',
        "Brasil, Uruguay, Argentina, Islas Caimán, Rusia", "ordered_export_destinations",
        "yes", "yes", "no", "no", "no", "strong", "non-top benchmark",
        "Confirms China was not a leading export destination.",
    ),
    s(
        "sur_wits_2003", "Suriname", "SUR", "Latin America", "not in supplied donor list",
        "8", "2003", "WITS/World Bank", "international_statistics", "International", "undated",
        "https://wits.worldbank.org/CountryProfile/en/Country/SUR/Year/2003/TradeFlow/EXPIMP/Partner/by-country",
        "Suriname trade by partner 2003", "en", "retrospective rank audit",
        'WITS Suriname export partners 2003 China',
        "Unspecified, Belgium, United Arab Emirates, Guyana, India", "ordered_export_destinations",
        "yes", "yes", "no", "no", "no", "strong", "archive-limited benchmark",
        "No local contemporary source was recovered; do not code public absence from this alone.",
    ),
    s(
        "bol_ibce_2015", "Bolivia", "BOL", "Latin America", "not in supplied donor list",
        "4", "2015", "IBCE", "business_statistics", "Bolivia", "2015",
        "https://ibce.org.bo/documentos/informacion-mercado/2015/Bolivia-exportacion-segun-pais-destino-gestion-2015.pdf",
        "Bolivia: exportación según país de destino, gestión 2015", "es",
        "benchmark year: 2015",
        'site:ibce.org.bo Bolivia exportación país destino China 2015',
        "China, quinto destino, 5 por ciento", "export_destination_5",
        "yes", "yes", "no", "yes", "yes", "strong", "non-top benchmark",
        "Domestic business-statistics sheet conflicts mildly with the project rank-4 flag but agrees China was non-top.",
    ),
    s(
        "bol_mefp_2015", "Bolivia", "BOL", "Latin America", "not in supplied donor list",
        "4", "2015", "Ministerio de Economía y Finanzas Públicas", "official_report", "Bolivia", "2016",
        "https://www.economiayfinanzas.gob.bo/sites/default/files/2022-11/memoria2015.pdf",
        "Memoria de la economía boliviana 2015", "es", "following year: 2015--2016",
        'site:economiayfinanzas.gob.bo memoria 2015 China exportaciones Bolivia',
        "Brasil, Argentina y Estados Unidos", "leading_export_destinations",
        "yes", "yes", "yes", "yes", "yes", "strong", "non-top benchmark",
        "Domestic official report identifies the leading export destinations without China among the top three.",
    ),
]


SEARCHES = {
    "Argentina": [
        'Argentina China "segundo destino" exportaciones 2007',
        'Argentina China desplazó Chile exportaciones 2007',
        'Cristina visita China 2010 "segundo destino" exportaciones',
    ],
    "Colombia": ['Colombia China "segundo destino" exportaciones 2014 DANE'],
    "Costa Rica": ['Costa Rica China "segundo destino" exportaciones 2007 PROCOMER'],
    "Ecuador": ['Ecuador China segundo destino exportaciones 2015'],
    "Jamaica": ['Jamaica China second export destination 2004'],
    "Venezuela": ['Venezuela China segundo destino exportaciones 2007'],
    "Malta": ['Malta China largest export destination 2011 Hong Kong'],
    "Singapore": [
        'Singapore China second goods export destination 2005',
        'site:mti.gov.sg Singapore China 4th largest trading partner 2005',
        'site:nas.gov.sg Singapore China top trading partner 2013 trade performance',
        'site:mfa.gov.sg since 2013 China Singapore largest trading partner',
    ],
    "Chad": ['Tchad Chine deuxième destination exportations 2004'],
    "Georgia": ['Georgia China export destination rank 2004'],
    "Guatemala": ['Guatemala China export destination rank 2005'],
    "Paraguay": ['Paraguay China exportaciones destino 2005 relaciones diplomáticas'],
    "Suriname": ['Suriname China export destination 2003'],
    "Bolivia": ['Bolivia China destino exportaciones 2015 ranking'],
}


def slug(value: str) -> str:
    value = re.sub(r"[^a-z0-9]+", "_", value.lower())
    return value.strip("_")[:90] or "source"


def relative(path: Path) -> str:
    return str(path.relative_to(ROOT))


def extension(url: str, content_type: str) -> str:
    suffix = Path(urllib.parse.urlparse(url).path).suffix.lower()
    if suffix in {".pdf", ".html", ".htm", ".txt", ".json"}:
        return suffix
    if "pdf" in content_type.lower():
        return ".pdf"
    return ".html"


def download(source: Source) -> dict[str, str]:
    country_dir = RAW_DIR / source.iso3c.lower()
    country_dir.mkdir(parents=True, exist_ok=True)
    base = country_dir / slug(source.source_id)
    metadata_path = base.with_suffix(".metadata.json")
    result = {
        "fetch_status": "not_attempted",
        "http_status": "",
        "content_type": "",
        "size_bytes": "0",
        "raw_file": "",
        "raw_sha256": "",
        "fetch_error": "",
    }
    if metadata_path.exists():
        cached = json.loads(metadata_path.read_text(encoding="utf-8"))
        cached_fetch = cached.get("fetch", {})
        raw_file = cached_fetch.get("raw_file", "")
        if cached_fetch.get("fetch_status") == "ok" and raw_file:
            raw_path = ROOT / raw_file
            if raw_path.exists():
                cached["source"] = asdict(source)
                metadata_path.write_text(
                    json.dumps(cached, ensure_ascii=False, indent=2), encoding="utf-8"
                )
                return {key: str(cached_fetch.get(key, "")) for key in result}
    request = urllib.request.Request(source.url, headers={"User-Agent": USER_AGENT})
    body = b""
    for attempt in range(3):
        try:
            with urllib.request.urlopen(request, timeout=25) as response:
                body = response.read()
                result["http_status"] = str(getattr(response, "status", ""))
                result["content_type"] = response.headers.get("Content-Type", "")
                result["fetch_status"] = "ok"
            break
        except urllib.error.HTTPError as error:
            result["fetch_status"] = "http_error"
            result["http_status"] = str(error.code)
            result["content_type"] = error.headers.get("Content-Type", "")
            result["fetch_error"] = str(error)
            body = error.read()
            break
        except Exception as error:  # noqa: BLE001 - exact failure is audit evidence
            result["fetch_status"] = "error"
            result["fetch_error"] = repr(error)
            if attempt < 2:
                time.sleep(1.5 * (attempt + 1))

    if body:
        raw_path = base.with_suffix(extension(source.url, result["content_type"]))
        raw_path.write_bytes(body)
        result["raw_file"] = relative(raw_path)
        result["size_bytes"] = str(len(body))
        result["raw_sha256"] = hashlib.sha256(body).hexdigest()

    metadata = {
        "source": asdict(source),
        "accessed_at": ACCESSED_AT,
        "fetch": result,
    }
    metadata_path.write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    return result


def write_csv(rows: list[dict[str, str]]) -> None:
    REPORT_DIR.mkdir(parents=True, exist_ok=True)
    columns = list(asdict(SOURCES[0]).keys()) + [
        "accessed_at",
        "fetch_status",
        "http_status",
        "content_type",
        "size_bytes",
        "raw_file",
        "raw_sha256",
        "fetch_error",
        "raw_preserved",
        "countable_for_rank_salience",
    ]
    with SOURCE_CSV.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=columns)
        writer.writeheader()
        writer.writerows(rows)

    with SEARCH_LOG_CSV.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=["country", "query", "accessed_at", "interpretation_rule"],
        )
        writer.writeheader()
        for country, queries in SEARCHES.items():
            for query in queries:
                writer.writerow(
                    {
                        "country": country,
                        "query": query,
                        "accessed_at": ACCESSED_AT,
                        "interpretation_rule": (
                            "A missing accessible result is weak observation, not evidence of absence."
                        ),
                    }
                )


def write_checksums() -> None:
    lines = []
    for path in sorted(RAW_DIR.rglob("*")):
        if not path.is_file() or path == CHECKSUMS:
            continue
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        lines.append(f"{digest}  {relative(path)}")
    CHECKSUMS.write_text("\n".join(lines) + "\n", encoding="utf-8")


def validate(rows: list[dict[str, str]]) -> None:
    ids = [row["source_id"] for row in rows]
    if len(ids) != len(set(ids)):
        raise RuntimeError("Duplicate source_id in source register")
    if not all(row["url"].startswith("https://") for row in rows):
        raise RuntimeError("All source URLs must use HTTPS")
    if not all(row["accessed_at"] for row in rows):
        raise RuntimeError("Missing access timestamp")
    countries = {row["country"] for row in rows}
    missing = set(SEARCHES) - countries
    if missing:
        raise RuntimeError(f"Countries without registered evidence: {sorted(missing)}")
    SOURCE_CSV.read_text(encoding="utf-8")
    SEARCH_LOG_CSV.read_text(encoding="utf-8")


def main() -> None:
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    REPORT_DIR.mkdir(parents=True, exist_ok=True)
    rows: list[dict[str, str]] = []
    for source in SOURCES:
        fetch = download(source)
        row = asdict(source)
        row.update({"accessed_at": ACCESSED_AT, **fetch})
        raw_preserved = fetch["fetch_status"] == "ok" and bool(fetch["raw_file"])
        countable = (
            raw_preserved
            and source.method_eligible == "yes"
            and source.local_or_official == "yes"
            and source.explicit_rank_language == "yes"
        )
        row["raw_preserved"] = "yes" if raw_preserved else "no"
        row["countable_for_rank_salience"] = "yes" if countable else "no"
        rows.append(row)
    write_csv(rows)
    write_checksums()
    validate(rows)
    print(
        json.dumps(
            {
                "sources": len(rows),
                "countries": len({row["country"] for row in rows}),
                "raw_ok": sum(row["raw_preserved"] == "yes" for row in rows),
                "countable_rank_sources": sum(
                    row["countable_for_rank_salience"] == "yes" for row in rows
                ),
                "source_csv": relative(SOURCE_CSV),
                "search_log_csv": relative(SEARCH_LOG_CSV),
                "checksums": relative(CHECKSUMS),
            },
            ensure_ascii=False,
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
