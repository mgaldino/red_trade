# RDD Trade — Foreign Policy Impact of Trade Status Gains

## Projeto
Paper: "The Foreign Policy Impact of Trade-Based Status Gains: When China Overtakes the US as Top Trade Partner". Em Revise & Resubmit. Tambem submetido ao Simposio FGV-USP em 2026-04-10 (versao anonimizada: `paper_v4_anonymous.Rmd` / `output/paper_v4_anonymous.pdf`, folha de rosto apenas com titulo e abstract de 139 palavras).

SDiD principal (predetermined core, sem ajuste efetivo de covariáveis): ATT=-0.272 (SE placebo 0.130), p normal bilateral=0.036, IC95 [-0.527, -0.017]; rank placebo direcional 3/96 (p=0.031), rank absoluto bilateral 7/96 (p=0.073). Cross-country IFE goods-only status-current (5 anos, restricted risk set): ATT=-0.101 (SE 0.039), p=0.010; robusto em 3/5/7 anos e clean sample (p 0.003-0.019). Fonte: `data/processed/diagnostics/paper_v4_brazil_sdid_predetermined_core/` e targets `china_top_m2_goods_status_current_*`. Pipeline completo (~3h30min rebuild).

Autor: Manoel Galdino (DCP-USP).

## Versionamento

- Tag `v4.2` criada em 2026-05-18 como snapshot pré-revisão de teoria e painel cross-country (`paper_v4.Rmd` no commit `1b45624`).
- Arquivo ativo do paper: `paper_v4.Rmd`.
- Para consultar o snapshot: `git show v4.2:paper_v4.Rmd`.

## Estado recente

- **2026-08-23 — parecer de inferência causal + decisões aprovadas**: parecer completo em `quality_reports/2026-08-23_causal_did_inference.md` (veredito: adequada com ajustes). Decisões aprovadas pelo autor: (i) declarar contrato inferencial no texto — rank placebo direcional como teste primário (H1 é direcional na teoria), p do SE placebo como complemento, rank bilateral como sensibilidade conservadora explicada; (ii) check de robustez de mensuração com ideal points UNGA-DM (Fjelstul, Hug & Kilby 2026), pré-comprometido — resultado entra no paper seja qual for; plano em `quality_reports/plans/2026-08-23_ungadm_robustness_check.md`; (iii) NÃO fazer: promover spec commodity a principal, estender pós além de 2015/16, ampliar donor pool, conformal inference (p mínimo 1/19 ≈ 0.053 com T=19). Alternativas descartadas documentadas no parecer, seção 9.
- **2026-05-20 — coarse review, comentários menores**: o parecer local `coarse-review` gerou 26 comentários específicos. Após triagem do autor, C01-C16 e C18-C26 foram implementados ou resolvidos em `paper_v4.Rmd`; C17 ficou deliberadamente deferido. Plano e pendências filtradas estão em `quality_reports/coarse_review/plan_minor_comments_coarse_review_2026-05-20.md` e `quality_reports/coarse_review/pendencias_minor_comments_coarse_review_2026-05-20.md`.

## Pendência alta

- **2026-08-23 — contrato inferencial no texto (tarefa do autor)**: declarar na seção de desenho/identificação de `paper_v4.Rmd` que o teste primário do Brazil SDiD é o rank placebo direcional (justificado pela H1 direcional pré-declarada), aplicado uniformemente (inclusive no diagnóstico de direitos humanos). Movimentos associados: figura da distribuição placebo (dados já em `placebo_distribution.csv`, lidos no Rmd linha ~305 e nunca usados), painel único de inferência (aproveitar reforma da Tabela 2), resumo inferencial dos dois desenhos na introdução. Ver parecer 2026-08-23, seções 3-4 e 7.
- **2026-08-23 — check UNGA-DM EXECUTADO; incorporação ao texto pendente (autor)**: resultados finais em `quality_reports/ungadm_outcome_robustness/2026-08-23_final_report.md`. Brazil SDiD MAIS forte sob UNGA-DM (ATT -0.335, p normal 0.009, rank direcional 2/96 p=0.021, rank bilateral 3/96 p=0.031 — todas as convenções <5%); painel IFE em janela comum com linhas idênticas ATENUA (BSV -0.095 p=0.016 r*=2 vs UNGA-DM -0.027 p=0.573 r*=1; truncamento de janela descartado como causa). Por pré-compromisso, ambos entram no paper (apêndice + parágrafo de sensibilidade de mensuração na seção cross-country); BSV segue como outcome principal. Revisão causal independente CONCLUÍDA: **endossado com ressalvas** (`quality_reports/ungadm_outcome_robustness/2026-08-23_independent_causal_review.md`) — antes de frase interpretativa no texto sobre o painel, rodar o 2×2 (BSV/DM × r=1/2), pois a atenuação está confundida com a seleção de fatores; claim sustentável para o paper: painel "sensível à fonte de mensuração", não "não sobrevive"; SDiD: "todas as convenções <5%", sem promover o 2/96. Ver PENDING.md para a lista completa pós-revisão.
- **Contagens cross-country (2026-05-12) — RESOLVIDA em `paper_v4.Rmd`**: o abstract atual não contém contagens de tratados; o manuscrito ativo usa 35/126 tratados/controles (janela 5 anos). `paper_v4_anonymous.Rmd` (snapshot FGV-USP de 2026-04) permanece integralmente desatualizado (abstract antigo, "four of the eight", desenho CS-DiD antigo) — cobrado pela regra geral de sincronizar derivados antes de qualquer uso externo (ver `PENDING.md`, "Materiais derivados").

## Estrutura do repositorio
```
red_trade/
  red_trade.Rproj              # Projeto R
  _targets.R / _targets.yaml   # Pipeline targets
  renv/ + renv.lock            # Dependencias travadas
  paper_v4.Rmd                 # Paper atual (R&R)
  paper.Rmd ... paper_v3.Rmd   # Versoes anteriores (.Rmd sources)
  synth-trade-china.bib        # Bibliografia
  scripts/                     # Scripts R de analise
  data/                        # Dados processados + brutos
  raw data/                    # Dados brutos (24 subdirs)
  output/                      # PDFs compilados, logs, figuras
  references/                  # PDFs de papers citados
  replication package/         # Pacote de replicacao para submissao
  presentations/               # Slides
  quality_reports/             # Reviews
```

## Stack
- R (renv para dependencias, targets pipeline, fixest)
- Execucao via `targets::tar_make()`
- Cache local: `folha_scrape_cache.rds`, `wb_data_cache.rds` (determinismo sem API)
- Dados: Dataverse DOI https://doi.org/10.7910/DVN/M97OCJ

## Regras de trabalho

### Separacao de papeis
- **O agente que implementa NAO revisa. Quem revisa NAO implementa.** Usar agentes separados para cada funcao.

### Autoria
- **O autor escreve o paper.** NAO redigir secoes ou texto a menos que o autor peca explicitamente.
- Em prosa de manuscrito e relatórios para o autor/leitor, evitar o jargão `spell`/`treatment spell`. Usar `treatment entry/onset`, `treated periods`, ou descrição substantiva do parceiro deslocado. `Spell` pode aparecer apenas como nome interno herdado de variável/arquivo quando tecnicamente necessário.

### Workflow
- NAO rodar scripts sem aprovacao do usuario
- NAO commitar sem instrucao explicita
- NAO incorrer custos de API externos sem aprovacao explicita previa (informar: o que, quantas chamadas, custo estimado)
- Skills que exigem permissao devem ser rodadas em foreground
- Sempre ler o arquivo antes de propor mudancas
- Para imagens e documentos digitalizados, usar Read tool (VLM) diretamente — zero custo adicional
