# Revisão de código: migração UNGA-DM — commit `6861b65`

## Resumo executivo

Todos os achados substantivos das rodadas 1 e 2 foram corrigidos. O DAG de targets é acíclico, os gates solicitados são ancestrais das computações caras, os quatro baselines têm hashes válidos e o ciclo global envolvendo funções UNGA-DM foi eliminado.

## Nota geral: A

## Veredito: PASS

### Problemas críticos

Nenhum.

### Melhorias importantes

Nenhuma.

### Adjudicação dos achados anteriores

| Achado | Evidência atual | Resultado |
|---|---|---|
| R1.1 — gate de validação antes do master | Dependência explícita em `_targets.R:642` | Resolvido |
| R1.2 — gate comum antes dos quatro fits e bootstrap | `_targets.R:832`, `_targets.R:861` e `_targets.R:912` | Resolvido |
| R1.3 — fatores selecionados dinamicamente | Seleções `r.cv` passam ao bootstrap em `_targets.R:917` e são verificadas em `scripts/functions_ungadm_targets_migration.R:1940` | Resolvido |
| R1.4 — finitude da grade fixa | Gate explícito em `scripts/functions_ungadm_targets_migration.R:2131` | Resolvido |
| R1.5 — auditoria de ausência BSV | Classificação e exclusão em `scripts/functions_ungadm_targets_migration.R:1167` | Resolvido |
| R1.6 — hashes dos quatro baselines | Manifesto e validação em `scripts/functions_ungadm_targets_migration.R:1009` | Resolvido |
| R1.7 — colunas contratuais obrigatórias | Requisitos explícitos em `scripts/functions_ungadm_targets_migration.R:1120` e `scripts/functions_ungadm_targets_migration.R:1259` | Resolvido |
| R1 — fingerprint do orquestrador | Corpo recebido como argumento em `scripts/functions_ungadm_targets_migration.R:1699` e capturado via `sys.function()` em `scripts/functions_ungadm_targets_migration.R:1776` | Resolvido |
| R2.1 — gate do painel antes dos ranks | Dependência explícita em `_targets.R:705` | Resolvido |
| R2.2 — hashes ancestrais do fit, SE e ranks | Gate inserido antes do bundle em `_targets.R:660`; ancestralidade confirmada programaticamente | Resolvido |
| R2.3 — flags contraditórias BSV/UNGA-DM | Exclusão conjunta por flag e valor em `scripts/functions_ungadm_targets_migration.R:1167` e bloqueio no gate em `scripts/functions_ungadm_targets_migration.R:1283` | Resolvido |

### Auditoria do DAG

- `targets::tar_validate()`: **PASS**.
- Manifesto: 336 targets, 48 ligados ao bloco UNGA-DM.
- DAG somente de targets: 336 vértices, 537 arestas, acíclico.
- Ancestralidades confirmadas: hashes → fit; hashes → SE; hashes → ranks; gate do painel → ranks.
- `tar_network()` completo ainda falha porque o grafo global não é DAG.
- Decomposição atual: um único componente fortemente conexo, sem qualquer símbolo UNGA-DM: `.sdid_code_fingerprint`, `sdid_placebo_estimates` e `sdid_rank_distribution`, em `scripts/diagnostics/sdid_placebo_helpers.R:206`.
- No commit pai `f2d3572`, havia também o SCC UNGA-DM `run_ungadm_paired_bootstrap_candidate ↔ ungadm_paired_code_fingerprint`. Ele desapareceu no commit atual.
- Os helpers SDiD remanescentes não foram modificados por `6861b65`; portanto, o ciclo restante é preexistente e externo ao commit revisado.

### Verificações executadas

- Parse dos três arquivos R: **PASS**.
- Sete hashes — três insumos brutos e quatro baselines SDiD — correspondem exatamente ao contrato.
- Teste oficial com stubs: `ALL_STATIC_UNGADM_MIGRATION_TESTS_PASSED`.
- Casos adversariais adicionais para flags `FALSE/NA`, valores finitos e valores ausentes: **PASS**.
- Fingerprint muda quando o corpo do orquestrador muda e não cria autorreferência: **PASS**.
- Worktree permaneceu limpo durante a revisão.
- Nenhum `tar_make`, modelo, placebo ou bootstrap econométrico foi executado.

### Sugestão não bloqueante

Há apenas uma linha em branco adicional no fim de `migration/review_r_ungadm_round2.md:52`, detectada por `git diff --check`. É exclusivamente cosmética e não afeta o PASS.

### Pontos positivos

A correção faz o gateamento no DAG real, testa os casos adversariais que motivaram a rodada 2 e remove o ciclo UNGA-DM sem mascarar o débito técnico preexistente dos helpers SDiD.
