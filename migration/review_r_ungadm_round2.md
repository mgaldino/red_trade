# Revisão independente R — migração UNGA-DM, rodada 2

- Sessão independente: `01a060ae-de02-7923-a437-e86189f86d6c`
- Commit revisado: `f2d3572b48d8e44ccc3ab8246d8a6848d185def7`
- Restrições observadas: revisão somente leitura; nenhum modelo, placebo,
  bootstrap econométrico ou `tar_make()` executado; o revisor não editou
  arquivos.
- Nota: **B**.
- Veredito: **FAIL**.

## Resumo executivo

Os sete achados literais da rodada 1 e a observação sobre o fingerprint foram
corrigidos. Permaneceram três falhas adicionais relacionadas a gates e
consistência da janela comum. Elas não demonstram erro nos resultados
congelados atuais, mas violam o contrato de execução protegida.

## Melhorias importantes

1. `ungadm_sdid_rank_distribution_candidate` dependia diretamente do bundle,
   sem depender de `ungadm_sdid_panel_gate_candidate`. Um build seletivo ou
   paralelo poderia iniciar as 96 atribuições antes de validar completude,
   unidade e janela do painel.
2. O gate dos hashes dos quatro baselines SDiD precedia a comparação numérica,
   mas não era ancestral do fit, do SE de 20.000 replicações nem da
   distribuição de ranks. Um baseline alterado ainda permitia computação cara
   antes do bloqueio.
3. `dropped_rows` tratava `outcome_observed = FALSE` como BSV ausente, mas
   `complete_outcomes` verificava apenas se `abs_distance_china` era não
   ausente. Em fixture adversarial, uma linha com flag falsa e valor finito era
   simultaneamente auditada como ausente, mantida em `common_rows` e aceita
   pelos gates.

## Sugestão

O fingerprint passou a incluir o corpo do orquestrador e invalidou corretamente
o checkpoint quando esse corpo mudou. Entretanto, a autorreferência do
fingerprint e a referência mútua com o orquestrador fizeram `tar_network()`
padrão falhar por ciclo entre funções globais. `targets::tar_validate()` e o
DAG apenas de targets continuaram passando, mas a regressão prejudica a
auditoria visual completa.

## Verificações do revisor

- parse dos três arquivos R: `PASS`;
- manifesto estático: 336 targets, 48 UNGA-DM;
- `targets::tar_validate()`: `PASS`;
- teste estático oficial: `ALL_STATIC_UNGADM_MIGRATION_TESTS_PASSED`;
- hashes SDiD e brutos: correspondência exata;
- seleção CV dinâmica, contrastes, finitude e checkpoint/resume com stubs:
  `PASS`.

