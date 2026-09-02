# Contrato de migração: evidência de status

## Decisão autoral e escopo

Este contrato implementa a decisão aprovada de manter somente a aquisição HTTP fora do
`targets`. Os arquivos brutos e as codificações autorais permanecem congelados e
versionados; parsing, validação, junções, contagens, resumos por país e tabelas do
apêndice passam a ser construídos dentro do grafo.

O bloco inclui apenas os dois coletores que alimentam diretamente a auditoria de
recuperabilidade no apêndice de `paper_v4.Rmd`:

- `scripts/diagnostics/collect_status_cue_salience_sources.py`;
- `scripts/diagnostics/collect_ex_top1_salience_sources.py`.

`scripts/diagnostics/collect_un_process_tracing_documents.py` fica fora deste bloco. Ele
produz um diagnóstico separado sobre documentos da ONU, não é lido pelo manuscrito
ativo nem pelos targets da auditoria de status.

Nenhum coletor será executado durante esta migração sem autorização específica.

## Fronteira de responsabilidade

### Fora do `targets`

Os coletores Python podem:

1. fazer requisições HTTP;
2. reutilizar respostas brutas já arquivadas;
3. preservar respostas, erros, metadados de fetch, planos de busca e checksums dentro
   de `data/raw/`;
4. registrar logs de aquisição.

O manifest congelado nunca é reescrito pelo coletor. Uma recuperação de arquivo já
manifestado só é promovida ao caminho contratado quando os bytes adquiridos coincidem
com o SHA-256 original. Respostas diferentes e fontes novas ficam em um diretório de
staging imutável, com log e manifest próprios, até revisão e refreeze autoral separados.

Os coletores não podem produzir ou sobrescrever os CSVs de codificação, códigos por
país, comparações ou tabelas do apêndice.

### Insumos congelados do `targets`

- os manifests `checksums.sha256` e todos os arquivos por eles enumerados;
- `status_cue_source_evidence.csv` e `ex_top1_source_evidence.csv`, tratados daqui em
  diante como ledgers autorais de evidência-fonte;
- um CSV pequeno de overrides autorais para os códigos de status;
- um CSV pequeno de anotações autorais de lacunas do benchmark do incumbente;
- o arquivo congelado de identificação do incumbente;
- o plano bruto de busca, usado para recuperar o universo histórico de 14 casos.

Uma alteração futura em codificação autoral deve modificar explicitamente o ledger ou
o arquivo de overrides e passar novamente pelos gates; não pode ser efeito colateral de
uma nova resposta HTTP.

### Dentro do `targets`

- leitura e validação dos manifests e hashes brutos;
- validação de schemas, chaves, URLs, datas, ponteiros `raw_file` e vocabulários;
- construção dos códigos de status por país;
- construção dos códigos de recuperabilidade do antigo incumbente;
- junção comparativa das duas auditorias;
- escrita dos três CSVs derivados usados pelo pipeline;
- construção das tabelas `recoverability_table` e `afr_context_table` consumidas pelo
  manuscrito.

Os três CSVs históricos permanecem como referências congeladas. Os writers do novo
grafo gravam cópias byte a byte equivalentes em
`data/processed/targets_migration/status_evidence/`; o consumidor do apêndice usa essas
cópias somente depois do gate em memória.

## Baseline congelado

### Arquivos brutos

| Diretório | Arquivos totais | Entradas no manifest | SHA-256 do `checksums.sha256` |
|---|---:|---:|---|
| `data/raw/status_cue_salience/` | 90 | 89 | `9be41ee4805289fb6b32bf21cea39146363053d2a2970d26e20e9bc1aaaa0675` |
| `data/raw/ex_top1_salience/` | 49 | 48 | `7f92a5822b396ee204e9e8eb4ea5682d791abdddecf5758134b97447ee69d8c3` |

O total é 139 arquivos e 22.808.647 bytes (21,75 MiB), mantidos no Git e no
pacote de replicação por decisão do autor.

### Ledgers autorais de evidência-fonte

| Arquivo | Dimensão | SHA-256 |
|---|---:|---|
| `data/processed/status_cue_salience/status_cue_source_evidence.csv` | 21 × 25 | `e24bfca356622e72702f35252c7a1a5c0ffa3fd4c76a1810011a17c2d1e27f99` |
| `data/processed/ex_top1_salience/ex_top1_source_evidence.csv` | 22 × 36 | `c7f14d595af04ec5bad108897bf150a833bbe56123e1229857c38eb88f9ec1fc` |

### Arquivos derivados que devem ser reproduzidos

| Arquivo | Dimensão | SHA-256 de referência |
|---|---:|---|
| `data/processed/status_cue_salience/status_cue_country_codes.csv` | 14 × 14 | `ca2fb896d5a6c7614ce1ad7907368b409ecf209a97367d00b19236c70d709533` |
| `data/processed/ex_top1_salience/ex_top1_country_codes.csv` | 14 × 25 | `568e1a9f6461347de4a74abc5b26c32770c2220cdd286cb91bf655a4f56fdce4` |
| `data/processed/ex_top1_salience/status_cue_vs_ex_top1_coverage.csv` | 14 × 18 | `f45ae615f6c2e7f0fe7582f08878f64e7f77526bfe7557307d2319693e8925b9` |

O input congelado de identificação do incumbente é
`data/processed/diagnostics/incumbent_salience_moderators_2026-05-19.csv`, SHA-256
`c170d884d943c9a133849e4676a9cbff1236ce8a2c4ea9d8f68cead364b4f08f`.

## Universo da auditoria

A evidência coletada cobre 14 países do desenho anterior: `SLB`, `PHL`, `AGO`, `CHL`,
`BRA`, `MYS`, `AUS`, `SLE`, `URY`, `MMR`, `SAU`, `GAB`, `KWT` e `QAT`.

Esse universo não coincide com os 35 tratados da especificação principal atual. A
migração preserva o universo empírico efetivamente pesquisado e não recodifica os 21
casos adicionais como ausência de evidência. Ampliar a auditoria exige nova coleta e
nova codificação autoral, ambas fora do escopo desta migração mecânica.

As tabelas devem, por isso, ser interpretadas como auditoria de recuperabilidade dos 14
casos pesquisados, não como cobertura completa da amostra tratada atual.

## Invariantes e gates

1. Os manifests têm exatamente 89 e 48 entradas, sem caminhos absolutos, duplicados,
   travessia `..` ou arquivos ausentes.
2. Cada arquivo bruto coincide com o SHA-256 declarado.
3. Os ledgers têm 21 e 22 chaves-fonte únicas e coincidem com os hashes congelados.
4. Todos os `raw_file` não vazios pertencem ao diretório bruto correto, existem e
   constam do manifest correspondente. `url` e todo `archive_url` não vazio devem
   ser URIs ASCII HTTP(S) sintaticamente válidas, com hostname DNS ou IPv4 e porta
   válidos, sem caracteres crus fora da gramática URI ou escapes percentuais
   malformados. `accessed_at` deve ser um timestamp RFC 3339 válido.
5. O universo coincide exatamente, em código ISO3, nome e ano de entrada, com os 14
   casos contratados; anos fracionários, códigos inválidos ou substituições são erro.
6. Os códigos usam somente os vocabulários contratuais; flags booleanas não admitem
   valores implícitos ou ausentes.
7. A derivação nova deve reproduzir as três tabelas de referência em nomes e ordem de
   colunas, tipos, chaves, dimensões, valores e SHA-256 serializado antes de qualquer
   writer.
8. As duas tabelas entregues ao manuscrito devem ser idênticas, em conteúdo, às tabelas
   produzidas a partir do baseline atual.
9. Nenhum target do bloco pode depender de rede, relógio de execução ou descoberta do
   arquivo `incumbent_salience_moderators_*` por ordenação de nomes.
10. Os coletores Python alterados precisam de revisão independente `review-python` com
    `PASS`; o código R precisa de revisão independente `review-r` com `PASS`.
11. A promoção de uma recuperação congelada deve vincular verificação e cópia aos
    mesmos bytes, revalidar o destino e nunca remover por pathname um arquivo que
    possa ter sido criado ou substituído concorrentemente.
12. Cada redirecionamento deve permanecer em HTTP(S). Toda execução que crie staging
    deve terminar com log e manifest próprios, inclusive quando uma linha falhar ou
    encontrar um destino concorrente; conflitos são bloqueantes e nunca apagam o
    arquivo concorrente.
13. Um destino que apareça entre o preflight e o processamento da linha deve ser
    revalidado contra o SHA-256 congelado. O store configurado para esta worktree deve
    ser seu `_targets/` local, nunca o store do checkout de `main`.
14. Nos coletores Python, a validação e a reutilização de arquivos brutos devem
    preservar o pathname lexical até a abertura e nunca seguir symlink no arquivo
    final. Symlink final, dangling symlink, diretório pai symlinkado e destino presente
    sem hash congelado são conflitos bloqueantes e não podem ser aceitos como cache.
15. Falhas de validação do arquivo congelado devem ser tipadas e convertidas pelos dois
    entrypoints em código de saída 2, inclusive quando o conflito já existe antes do
    preflight; erro de validação nunca pode escapar como código 0 ou exceção não tratada.

## Testes autorizados antes do build

Estão autorizados parse, compilação estática de Python, testes com fixtures temporárias,
validação de schemas/hashes, reconstrução em memória e comparação com os CSVs já
existentes. Não estão autorizados nesta etapa: executar os coletores, acessar a rede,
rodar modelos, bootstraps, placebos ou `targets::tar_make()`.
