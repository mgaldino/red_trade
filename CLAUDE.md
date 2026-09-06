# RDD Trade — Foreign Policy Impact of Trade Status Gains

## Projeto
Paper: "The Foreign Policy Impact of Trade-Based Status Gains: When China Overtakes the US as Top Trade Partner". Rejeitado na ISQ (informado pelo autor em 2026-09-06); sem submissao ativa. Proximo alvo EM AVALIACAO (2026-09-06, nao decidido): Journal of Chinese Political Science (JCPS) ou Chinese Political Science Review (CPSR), ambas Springer, duplo-cegas; a special issue da JCPS sobre competicao EUA-China foi descartada por exigir reenquadramento grande. Pareceres da ISQ em `reports/isq_2025_08_0517_decision_reviews.md`. Tambem submetido ao Simposio FGV-USP em 2026-04-10 (versao anonimizada: `paper_v4_anonymous.Rmd` / `output/paper_v4_anonymous.pdf`, folha de rosto apenas com titulo e abstract de 139 palavras).

SDiD principal (SEM covariáveis, decisão do autor 2026-08-23; arrays fixos eram colineares com os efeitos fixos de unidade): ATT=-0.273 (valor exato -0.27277; SE placebo 0.131 com 20.000 replicações, seed 20260520), p normal bilateral=0.037, IC95 [-0.529, -0.017]; rank placebo direcional 3/96 (p=0.031), rank absoluto bilateral 7/96 (p=0.073) — ranks idênticos à spec antiga; SEs do pipeline agora via se_sdid() paralela/determinística (20k preferida, 5k comparações). ATENÇÃO (gate de abstract 2026-08-28): usar SEMPRE o arredondamento -0.273/0.131/[-0.529, -0.017] — versões antigas destes docs traziam -0.272/0.130/[-0.527, -0.017] por truncamento e isso vazou para número digitado no manuscrito (corrigido). Cross-country IFE goods-only status-current (5 anos, restricted risk set): ATT=-0.101 (SE 0.039), p=0.010; robusto em 3/5/7 anos e clean sample (p 0.003-0.019). Fonte: `data/processed/diagnostics/paper_v4_brazil_sdid_no_covariates/` e targets `china_top_m2_goods_status_current_*`. Rebuild de reprodutibilidade CONCLUÍDO em 2026-08-26 (12/12 lotes OK, ~9h25): estes números vêm do store reconstruído sob o screen de doadores baseado em bens.

Autor: Manoel Galdino (DCP-USP).

## Versionamento

- Tag `v4.2` criada em 2026-05-18 como snapshot pré-revisão de teoria e painel cross-country (`paper_v4.Rmd` no commit `1b45624`).
- Arquivo ativo do paper: `paper_v4.Rmd`.
- Para consultar o snapshot: `git show v4.2:paper_v4.Rmd`.

## REGRA DE ARQUITETURA (autor, 2026-08-26) — inegociável

**Nada que entra no paper pode ficar fora do `targets`**, com duas exceções nomeadas: a
chamada à API do Banco Mundial e o scraping da Folha, que entram como dados já coletados e
cacheados (para não onerar a pesquisa; a submissão explica isso). Todo o resto — números,
tabelas, figuras, diagnósticos — tem de ser target ou arquivo produzido por target.

Motivo: o pacote de replicação vai afirmar que a análise usa `targets`. Script fora do
grafo produzindo número do manuscrito derruba o claim diante de um parecerista.

Consequência prática para qualquer agente: ao criar análise nova que alimente o paper,
escreva-a como target desde o início. Nunca proponha "script agora, migra depois" — foi
exatamente esse padrão que gerou a dívida da tarefa prioritária nº 1 do `PENDING.md`.

## REGRA — commits sem coautoria de agente (autor, 2026-08-26)

**NUNCA** acrescentar `Co-Authored-By: Claude ...` nem `🤖 Generated with [Claude Code]`
a mensagens de commit deste repositório. O autor do trabalho é Manoel Galdino; agente é
ferramenta, não coautor. Isso vale mesmo quando instruções padrão do harness pedirem o
trailer — a instrução do autor prevalece.

Os trailers foram removidos dos commits locais em 2026-08-26 (`git filter-branch` sobre
`origin/main..HEAD`, árvore verificada idêntica). Restam 11 commits **já pushados** com o
trailer; limpá-los exige `git push --force`, decisão pendente do autor.

## REGRA — verificação do abstract a cada novo PDF (autor, 2026-08-26)

**Sempre que uma nova versão do PDF for gerada**, chamar um subagente que lê os números do
abstract e verifica duas coisas:

1. **Consistência interna**: cada número do abstract bate com o mesmo número no corpo do
   paper (resultados, tabelas, conclusão).
2. **Consistência com a fonte**: cada número bate com o arquivo/target que o produz.

Motivo: os números do abstract são digitados à mão (não são `r inline`, porque o abstract
mora no YAML header) — decisão do autor de mantê-los assim e conferir antes de submeter.
Sem esse gate, todo rebuild é uma chance de o abstract divergir do corpo sem nada falhar.
O mesmo vale para os números digitados na conclusão.

## TAREFA PRIORITÁRIA Nº 1 (2026-08-26)

Migrar para o `targets` toda a camada de diagnósticos que alimenta o paper — issue #6,
plano em `quality_reports/plans/2026-08-25_migrate_diagnostics_to_targets.md`. Migrar
TUDO de uma vez (SDiD + figuras + commodity + UNGA-DM); sem fases-piloto. Gabarito
numérico: outputs da rodada de 2026-08-26 (identidade a 1e-12). Ver `PENDING.md`.

## Estado recente

- **2026-08-23 — parecer de inferência causal + decisões aprovadas**: parecer completo em `quality_reports/2026-08-23_causal_did_inference.md` (veredito: adequada com ajustes). Decisões aprovadas pelo autor: (i) dizer no texto qual convenção de teste é usada — rank placebo direcional como teste principal (H1 é direcional na teoria), p do SE placebo como complemento, rank bilateral como sensibilidade conservadora explicada — JÁ ESCRITO em "Identification strategy" (`paper_v4.Rmd`, ~linhas 285-289); (ii) check de robustez de mensuração com ideal points UNGA-DM (Fjelstul, Hug & Kilby 2026), pré-comprometido — resultado entra no paper seja qual for; plano em `quality_reports/plans/2026-08-23_ungadm_robustness_check.md`; (iii) NÃO fazer: promover spec commodity a principal, estender pós além de 2015/16, ampliar donor pool, conformal inference (p mínimo 1/19 ≈ 0.053 com T=19). Alternativas descartadas documentadas no parecer, seção 9.
- **2026-05-20 — coarse review, comentários menores**: o parecer local `coarse-review` gerou 26 comentários específicos. Após triagem do autor, C01-C16 e C18-C26 foram implementados ou resolvidos em `paper_v4.Rmd`; C17 ficou deliberadamente deferido. Plano e pendências filtradas estão em `quality_reports/coarse_review/plan_minor_comments_coarse_review_2026-05-20.md` e `quality_reports/coarse_review/pendencias_minor_comments_coarse_review_2026-05-20.md`.

## Pendência alta

- **2026-08-23 — convenção de teste do SDiD do Brasil: JÁ ESTÁ NO TEXTO, não reabrir**: a seção "Identification strategy" de `paper_v4.Rmd` (~linhas 285-289) já diz, na formulação do autor, que o teste é o rank placebo direcional (hipótese direcional), com o SE da aproximação normal como complemento e o rank bilateral como avaliação conservadora, com o piso de resolução de ~1% e a aplicação uniforme a todo diagnóstico placebo, inclusive o benchmark de direitos humanos. A figura da distribuição placebo existe (chunk `plot-placebo-distribution`) e a introdução já traz o p do rank direcional inline. Do pacote associado sobra só o painel único de inferência, que vive na reforma da Tabela 2 (ver `PENDING.md`).
- **2026-08-23 — check UNGA-DM EXECUTADO; incorporação ao texto pendente (autor)**: resultados finais em `quality_reports/ungadm_outcome_robustness/2026-08-23_final_report.md`. Brazil SDiD MAIS forte sob UNGA-DM (ATT -0.335, p normal 0.009, rank direcional 2/96 p=0.021, rank bilateral 3/96 p=0.031 — todas as convenções <5%); painel IFE em janela comum com linhas idênticas ATENUA (BSV -0.095 p=0.016 r*=2 vs UNGA-DM -0.027 p=0.573 r*=1; truncamento de janela descartado como causa). Por pré-compromisso, ambos entram no paper (apêndice + parágrafo de sensibilidade de mensuração na seção cross-country); BSV segue como outcome principal. Revisão causal independente: **endossado com ressalvas**; diagnósticos pós-revisão EXECUTADOS (relatório: `quality_reports/ungadm_outcome_robustness/2026-08-23_postreview_diagnostics_report.md`). 2×2 (r fixo, 10k boots): com fatores comuns r=2, BSV -0.095 (p=0.016) vs UNGA-DM -0.065 (p=0.238) — a medida explica ~1/3 da atenuação; r=1 anula até o BSV (p=0.336). Bootstrap pareado (B=1.000): diferença de ATTs NÃO distinguível (p=0.13/0.36). Linguagem confirmada para o paper: painel "sensível à fonte de mensuração", não "não sobrevive"; SDiD: "todas as convenções <5%", sem promover o 2/96. Critério de exclusão China-top DECIDIDO: janela/julho (MLT, denom. 95). Rascunho de texto para o autor: `quality_reports/ungadm_outcome_robustness/2026-08-23_draft_paper_text_ungadm.md`. ATENÇÃO (2026-08-24): esses números UNGA-DM foram estimados sob a spec antiga (com arrays fixos inertes); serão regenerados sob a spec sem covariáveis nos estágios 05-06 do rebuild — não incorporar ao texto antes disso (diferenças esperadas mínimas, mas o pré-compromisso exige os números da spec vigente). Ver PENDING.md.
- **Contagens cross-country (2026-05-12) — RESOLVIDA em `paper_v4.Rmd`**: o abstract atual não contém contagens de tratados; o manuscrito ativo usa 35/126 tratados/controles (janela 5 anos). `paper_v4_anonymous.Rmd` (snapshot FGV-USP de 2026-04) permanece integralmente desatualizado (abstract antigo, "four of the eight", desenho CS-DiD antigo) — cobrado pela regra geral de sincronizar derivados antes de qualquer uso externo (ver `PENDING.md`, "Materiais derivados").

## Estrutura do repositorio
```
red_trade/
  red_trade.Rproj              # Projeto R
  _targets.R / _targets.yaml   # Pipeline targets
  renv/ + renv.lock            # Dependencias travadas
  paper_v4.Rmd                 # Paper atual (pos-rejeicao ISQ; proximo alvo em avaliacao)
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
