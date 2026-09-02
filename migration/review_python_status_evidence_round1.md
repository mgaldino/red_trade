# Revisão de código: gate Python da migração de evidência de status

## Resumo executivo

O caminho padrão é realmente sem HTTP, `--acquire` é explícito, o processamento
derivado antigo não é chamado por `main()` e os hashes atuais coincidem com o
contrato. Porém, o ciclo de aquisição viola a integridade congelada e torna a
validação subsequente inconsistente. Isso bloqueia o gate.

Itens econométricos, seeds, vetorização e apresentação de tabelas/gráficos: N/A,
pois o escopo contém apenas aquisição e validação de arquivos.

## Nota geral: D

## Problemas críticos 🔴

1. **Uma aquisição efetiva refaz silenciosamente o baseline congelado e tende a
   invalidar a execução seguinte.**

   Com `--acquire`, arquivos ausentes deixam de ter o hash verificado. Depois do
   download, ambos os coletores regeneram e sobrescrevem o manifest. Assim, uma
   resposta diferente da cópia congelada recebe um novo hash em vez de provocar
   erro. Novos sidecars e logs entram no manifest, mas as contagens continuam
   fixadas em 89 e 48; a validação seguinte pode falhar por contagem. O fluxo
   também não consegue adquirir uma fonte verdadeiramente nova porque o ponteiro
   do ledger precisa já constar do manifest.

   Correção requerida: manter o manifest congelado imutável; verificar
   recuperações contra o hash original; colocar novas aquisições em staging com
   manifest append-only; exigir gate autoral separado para eventual refreeze.

## Melhorias importantes 🟡

1. A garantia de nunca sobrescrever raw não é forte: há janela entre `exists()` e
   `write_bytes()`. Sidecars e logs usam timestamps com resolução de um segundo.
   Usar criação exclusiva (`xb`/`O_EXCL`) e nomes garantidamente únicos.
2. Respostas HTTP de erro podem reaparecer como `cached_ok`; preservar o status
   armazenado no sidecar.
3. Restringir explicitamente aquisição a `http`/`https` e validar `timeout > 0`,
   `retries >= 1` e `backoff >= 0`.
4. Adicionar teste offline ponta a ponta que prove: default sem `urlopen`,
   aquisição somente com flag, manifest congelado preservado e nova validação
   bem-sucedida.

## Sugestões 🟢

- Mover as 44 funções legadas fora do caminho de `main()` para histórico após o
  gate.
- Remover o import não utilizado `field`.
- Transmitir respostas grandes em blocos para arquivo temporário exclusivo.

## Pontos positivos ✓

- `HEAD` confirmado em `231ab00`, base `05c1144`, sem alterações locais.
- Default sem HTTP e `--acquire` explícito nos dois entrypoints.
- Caminhos absolutos, `..` e symlinks resolvidos são rejeitados.
- Os 89 e 48 arquivos atuais passaram pela validação SHA-256.
- O processamento derivado legado não é alcançável por `main()`.
- Os quatro arquivos Python compilam em memória.

GATE: FAIL
