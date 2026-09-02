# Teste estático da migração: evidência de status

Data: 2026-09-02

## Escopo

Validação pré-build do bloco descrito em
`migration/contract_status_evidence.md`. Nenhum coletor, `tar_make()`, modelo,
bootstrap, placebo ou acesso à rede foi executado.

## Python

Comando:

```text
PYTHONPYCACHEPREFIX=/tmp/red_trade_pycache \
  python3 migration/test_status_evidence_collectors_static.py
```

Resultado final:

```text
ALL_STATIC_STATUS_EVIDENCE_PYTHON_TESTS_PASSED
```

Gates confirmados:

- o `main()` dos dois coletores não chama agregações, comparações ou writers de
  arquivos processados;
- os dois `main()` delegam somente aquisição bruta ao helper compartilhado;
- a execução padrão dos dois entrypoints retorna sem chamar a função de aquisição;
- os ledgers têm 21 e 22 linhas;
- arquivos brutos presentes são reutilizados e não sobrescritos;
- conteúdo adulterado e travessia de caminho são rejeitados;
- recuperação simulada só promove bytes que coincidem com o hash congelado;
- bytes divergentes e fontes novas permanecem em staging imutável até refreeze
  autoral separado;
- log, metadados e manifest do run ficam em staging e não alteram o manifest
  congelado;
- status HTTP de arquivos existentes é recuperado do sidecar, não inferido pelo
  nome;
- URLs não HTTP(S), opções inválidas, missing não recuperável e tentativas de
  overwrite exclusivo são rejeitados.

## R e DAG

Comando:

```text
Rscript --vanilla migration/test_status_evidence_migration_static.R
```

Resultado final:

```text
ALL_STATIC_STATUS_EVIDENCE_R_TESTS_PASSED
```

Gates confirmados:

- 89/89 hashes brutos de status e 48/48 hashes brutos do antigo incumbente
  coincidem com os manifests;
- os hashes e schemas dos ledgers autorais coincidem com o contrato;
- booleanos inválidos, ponteiros inseguros e chaves duplicadas são rejeitados;
- anos fracionários, datas impossíveis e URLs sem HTTP(S) válido são rejeitados;
- o universo deve coincidir exatamente com os 14 pares autorais de código, nome e
  ano; substituições preservando 14 linhas falham;
- o input congelado de identificação do incumbente coincide com o SHA-256
  contratado;
- as três derivações reproduzem os CSVs de referência em nomes e ordem de
  colunas, tipos, chaves, dimensões, valores e SHA-256 serializado: 14 × 14,
  14 × 25 e 14 × 18;
- `recoverability_table` e `afr_context_table`, as duas tabelas consumidas pelo
  manuscrito, são idênticas às versões construídas do baseline;
- `targets::tar_validate(callr_function = NULL)` passa;
- o DAG somente de targets, analisado com store temporário isolado do checkout
  principal, permanece acíclico;
- os file targets brutos são ancestrais dos outputs por país;
- o gate de derivação é ancestral das tabelas do apêndice.

## Condição de execução

Esses testes demonstram equivalência de transformações e topologia do DAG, não
um build completo. A execução de `targets::tar_make()` continua dependente de
autorização específica do autor.
