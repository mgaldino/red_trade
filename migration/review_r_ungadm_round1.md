# Revisão independente R — migração UNGA-DM, rodada 1

- Sessão independente: `01a0609a-9d5b-7e43-9459-a6913cea9f29`
- Escopo: `_targets.R`, `scripts/functions_ungadm_targets_migration.R`,
  `migration/test_ungadm_migration_static.R` e contrato UNGA-DM.
- Restrições observadas: revisão somente leitura; nenhum modelo, placebo,
  bootstrap ou `tar_make()` executado; o revisor não editou arquivos.
- Veredito: **C / FAIL**.

## Achados importantes

1. `ungadm_validation_gate_candidate` barrava somente arquivos de validação e
   a figura de overlay. O master aumentado e, por consequência, as cadeias
   analíticas não tinham dependência explícita desse gate.
2. Os quatro ajustes IFE de `r` fixo e o bootstrap pareado não dependiam
   explicitamente de `ungadm_common_window_gate_candidate`.
3. O contraste descrito como “procedure-selected” estava codificado como BSV
   `r = 2` versus UNGA-DM `r = 1`, embora a validação cruzada possa selecionar
   qualquer `r` em `0:3`. A seleção precisa ser dinâmica ou falhar
   explicitamente quando divergir desses valores.
4. O gate final exigia inferência finita para a tabela de comparação, mas não
   para a grade IFE de `r` fixo.

## Achados menores

5. A auditoria de linhas excluídas distinguia apenas o endpoint e a ausência
   do desfecho UNGA-DM, embora a janela comum também exclua ausência do
   desfecho BSV.
6. Os hashes contratuais dos quatro arquivos SDiD de referência não eram
   impostos antes da comparação numérica.
7. O uso de `intersect()` para colunas de tratamento/metadados permitia que
   uma coluna contratual ausente fosse silenciosamente ignorada.

## Observação adicional da implementação

O fingerprint do checkpoint pareado não incluía o corpo da função principal
que orquestra os draws. Alterações nessa função poderiam reutilizar um
checkpoint antigo; a correção deve incluir esse corpo no fingerprint.

