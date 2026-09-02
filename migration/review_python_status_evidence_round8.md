# Revisão independente Python: evidência de status — rodada 8

Commit revisado: `8c2ae320c81982bcd2debf5b5e5f26c72f8c04ff`, pai direto
`47ce9162ee1a678ffbcc0e412b459dbcc119274a`.

Revisor: sessão independente `01a0618d-a25b-7132-b285-1347fa55d662`, modo
somente leitura, aplicando `review-python`.

## Resultado

**Nota: A — GATE: PASS**

Não houve achados críticos, importantes ou menores.

## Correção da rodada 7

- `FrozenArchiveValidationError` representa de forma tipada uma falha do preflight.
- `validate_frozen_archive()` converte falhas da validação nesse tipo, preservando a
  causa original.
- Os dois `main()` capturam especificamente essa exceção e retornam código 2.
- As fixtures cobrem, antes do `main()`, `hash_mismatch`, arquivo não manifestado,
  symlink para bytes coincidentes e dangling symlink nos dois entrypoints; exigem
  retorno 2, preservação do concorrente e do manifest e ausência de staging.

## Reconfirmações

- pathname lexical e `O_NOFOLLOW` preservados;
- pais symlinkados, symlink final e dangling symlink rejeitados;
- arquivo regular coincidente revalidado pelo SHA-256 congelado e reutilizado;
- corridas depois do preflight classificadas antes de acesso à rede e novamente na
  promoção;
- concorrentes nunca sobrescritos ou removidos;
- manifests congelados somente lidos;
- staging criado sempre finalizado com log e manifest próprios;
- URLs iniciais, URLs de metadata e cada redirecionamento restritos a HTTP(S);
- cópia, hash e promoção vinculados ao mesmo descritor;
- nenhum processamento derivado chamado pelos dois coletores.

## Testes executados pelo revisor

- `git diff --check 47ce916 8c2ae32`: passou.
- Compilação integral em memória dos três módulos e do teste estático: passou, sem
  gerar bytecode.
- A suíte estática confirmou os dois `main()` como acquisition-only, a delegação ao
  helper compartilhado, 89 e 48 entradas nos manifests, ledgers com 21 e 22 linhas e
  modo padrão read-only.
- O sandbox somente leitura do revisor não oferecia diretório temporário gravável;
  portanto, as fixtures foram auditadas integralmente no código, mas não reexecutadas
  nessa sessão. A execução completa da suíte no ambiente de implementação havia
  passado e não foi contabilizada como teste independente.

Nenhum coletor real, acesso à rede, `tar_make()`, modelo, placebo ou bootstrap foi
executado. Nenhum arquivo foi criado ou alterado pelo revisor.
