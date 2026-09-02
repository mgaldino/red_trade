# Sétima revisão independente — SDiD Brasil + commodities/Tabela 5

Commit revisado: `6bc84d8b9da9c044f46d884fe6eacd9d8d05d691`.

Nota geral: **A**.

Veredito: **PASS sem ressalvas**.

A revisão foi estritamente estática, com a skill `review-r`. O revisor não
executou R, `targets`, testes, modelos, placebos, bootstrap, scans de dados ou
qualquer computação e não alterou arquivos.

## Achados por severidade

- Críticos: nenhum.
- Importantes: nenhum.
- Menores: nenhum.

## Fundamentação

O revisor confirmou que o fingerprint cobre toda a cadeia funcional relevante
aos checkpoints: execução paralela validada; leitura e escrita atômica;
estimação placebo e normalização de pesos; construção de covariáveis; ajuste
SDiD e cálculo de estimativa/RMSPE; validação e produção da distribuição de
ranks; e versão do `synthdid`. O digest entra nos fingerprints tanto dos
placebos quanto dos ranks.

O teste integrado foi julgado probatório: grava um checkpoint completo, mantém
caminho e rótulo, altera `sdid_mclapply_checked()`, reinicia o contador de
ajustes e exige três novas chamadas, uma por unidade. Isso distingue
recomputação integral de mera reutilização do checkpoint.

Também foram revalidados estaticamente os gates das rodadas anteriores:
comparador tolerante e fail-closed; rejeição de `Inf`, `NaN` e RMSPE negativo;
cobertura global parcial versus cinco anos no universo analítico; retry de
ranks com erro; checkpoints em lotes e atômicos; seed, replicações e common
random numbers; limite de BLAS; scan único do ITPD-E; file targets candidatos;
uso dos arquivos antigos apenas para comparação; e ausência de promoção
antecipada.
