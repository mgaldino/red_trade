# Dados brutos — piloto de coautoria na OMC

Fonte primária: [WTO Documents Online](https://docs.wto.org/dol2fe/Pages/FE_Search/FE_S_S001.aspx), consultado em 28 de agosto de 2026.

## Conteúdo

- `2026-08-28/search_title_*.json`: resultados preservados de buscas oficiais no campo de título, para 2000–2014, com `Brazil AND [partner]`. Cada arquivo contém a URL parametrizada, a contagem informada pelo portal e os registros expostos pela interface.
- `2026-08-28/validation_pdfs/`: 55 PDFs oficiais distintos usados nas validações manuais.
- `2026-08-28/*download_log*.json`: URL, caminho, tamanho, tipo MIME e SHA-256 de cada download solicitado.
- `2026-08-28/checksums.sha256`: hashes de todos os arquivos brutos, exceto o próprio manifesto de hashes.

Os arquivos iniciais incompletos de Índia e México foram preservados. As versões `retry1` são as extrações completas usadas no processamento. Não se deve apagar as tentativas iniciais: elas documentam a instabilidade observada ao alterar a paginação da interface.

## Cobertura e limites

As buscas por pares recuperaram 111 registros para China, 104 para Índia, 28 para África do Sul, 63 para México, 34 para Indonésia, 34 para Turquia e 77 para Argentina. Após deduplicação pelo `catalogue_id`, restaram 242 registros candidatos.

Esses arquivos não constituem um censo das submissões brasileiras. A presença dos dois países no título pode refletir autoria, menção, pergunta/resposta, contencioso ou a expressão “Hong Kong, China”. O campo “country concerned” do portal também não equivale a autoria. A autoria substantiva deve ser verificada no título autoral e na primeira página do PDF.

O portal é público, mas usa estado de sessão ASP.NET/Telerik, não expôs API pública documentada nesta auditoria e seu `robots.txt` declara `Disallow: /`. Por isso, não foi feito rastreamento automatizado amplo. As listas foram obtidas na interface pública; somente os URLs explícitos dos manifestos de validação foram baixados em baixo volume.

## Imutabilidade

Os dados brutos não devem ser sobrescritos. O downloader compara o SHA-256 quando o destino já existe e falha se o conteúdo divergir.

