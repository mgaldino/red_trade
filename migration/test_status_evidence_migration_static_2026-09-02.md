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
- URLs não HTTP(S), componentes URI inválidos, IPv6, opções inválidas (inclusive
  backoff não finito), missing não recuperável e tentativas de overwrite exclusivo
  são rejeitados;
- cada redirecionamento é revalidado e destinos fora de HTTP(S), inclusive `ftp:`,
  são bloqueados antes de serem abertos;
- os dois entrypoints percorrem o ramo `--acquire` ponta a ponta com HTTP
  substituído por fixture local, incluindo promoção, log e manifest de staging;
- promoção e publicação usam candidatos completos e criação exclusiva; sucesso
  concorrente, conflito e erro interno são classificados separadamente;
- publicações matching e conflitantes anteriores ao processamento da linha são
  revalidadas contra o hash congelado nos dois entrypoints, com códigos de saída 0 e 2;
- symlink final, dangling symlink, diretório pai symlinkado e concorrente não
  manifestado são rejeitados sem seguir o link; as fixtures cobrem os dois entrypoints,
  seus códigos de saída e a preservação do pathname concorrente;
- conflitos já presentes antes do preflight são falhas tipadas e fazem ambos os
  entrypoints retornarem código 2, sem criar staging ou alterar o arquivo/manifest;
- toda execução que cria staging termina com `fetch_log.json` e manifest próprios,
  inclusive em conflito ou falha inesperada de uma linha; arquivos concorrentes são
  preservados e o destino contratado nunca é removido.

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
- anos fracionários, datas impossíveis, timestamps RFC 3339 inválidos,
  hostnames/portas/componentes URI inválidos e `archive_url` não vazio sem HTTP(S)
  válido são rejeitados;
- timestamps RFC 3339 válidos com fração de segundo, `t`/`z` minúsculos e segundo
  intercalar no fim de junho/dezembro são aceitos;
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
- `_targets.yaml` configura o store local desta worktree, não o store de `main`;
- os file targets brutos são ancestrais dos outputs por país;
- o gate de derivação é ancestral das tabelas do apêndice.

## Condição de execução

Esses testes demonstram equivalência de transformações e topologia do DAG, não
um build completo. A execução de `targets::tar_make()` continua dependente de
autorização específica do autor.

O teste R foi executado com R 4.4.2 em `Rscript --vanilla`; as versões de alguns
pacotes instalados diferem do `renv.lock`, mas a equivalência serializada exata
passou. A execução controlada futura deve ativar o ambiente `renv` e registrar o
`sessionInfo()` completo.
