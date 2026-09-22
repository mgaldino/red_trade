# Relatório: public cue comercial da Austrália, 2006–2009

**Data da busca e verificação:** 22 de setembro de 2026  
**Unidade:** documento jornalístico nacional ou publicação oficial  
**Escopo:** evidência pública contemporânea sobre a posição da China nas
hierarquias comerciais da Austrália entre 2006 e 2009

## Resultado principal

A primeira pista pública nacional positiva diretamente recuperada é de **4 de
maio de 2007**. Naquele dia, a ABC informou que a China havia superado o Japão
como maior parceiro comercial da Austrália, usando a soma de importações e
exportações nos doze meses até março de 2007. Outra matéria da ABC repetiu a
classificação em 1º de setembro de 2007. Em contraste, as duas fontes
recuperadas para 2006 ainda colocavam a China em **segundo lugar**.

Essa cronologia não altera automaticamente a data de tratamento do estudo. A
pista de 2007 mede **comércio bilateral agregado**. Nenhum dos oito documentos
estabelece que a China já era o primeiro destino das **exportações de bens**,
que é a métrica da especificação cross-country principal. O DFAT confirma a
diferença: em 2007, a China foi a maior parceira bilateral em bens e serviços,
mas o Japão permaneceu como maior mercado de exportações.

## Evidência documental

**Tabela 1. Documentos recuperados sobre a posição comercial da China na
Austrália, 2006–2009.** `Cue amplo = sim` significa que o documento chama a
China de primeira sob a métrica que ele próprio utiliza; não significa
alinhamento com exportações goods-only.

| Publicação | Posição e métrica | Período do rank | Cue amplo | Avaliação e acesso |
|---|---|---|---:|---|
| [ABC, 28/06/2006](https://www.abc.net.au/news/2006-06-28/pm-hails-25b-china-gas-supply-deal/1788414) | China nº 2; parceiro comercial genérico | declaração corrente | Não | Matéria nacional arquivada; denominador não especificado. |
| [RBA, nov./2006](https://www.rba.gov.au/publications/smp/2006/nov/box-a.html) | China nº 2; destino de exportações de bens e serviços | ano-calendário 2005 | Não | Página verificada no navegador. O coletor não arquivou o artigo porque o endpoint de `robots.txt` retornou acesso negado. |
| [ABC, 04/05/2007](https://www.abc.net.au/news/2007-05-04/china-overtakes-japan-in-trade-with-aust/2540062) | China nº 1, Japão deslocado; importações + exportações | 12 meses até março de 2007 | **Sim** | Primeira pista nacional positiva recuperada; matéria arquivada. Bens versus bens + serviços não é explicitado. |
| [ABC, 01/09/2007](https://www.abc.net.au/news/2007-09-01/china-unseats-japan-as-australias-largest-trade/656322) | China nº 1, Japão deslocado; importações + exportações | julho e 12 meses até julho de 2007 | **Sim** | Segunda pista nacional positiva em 2007; matéria arquivada. Bens versus bens + serviços não é explicitado. |
| [DFAT, 19/05/2008](https://www.dfat.gov.au/news/media/Pages/australia-s-composition-of-trade-2007) | China nº 1; comércio bilateral de bens e serviços; Japão nº 1 nas exportações | ano-calendário 2007 | **Sim** | Confirmação oficial verificada no navegador. O coletor parou quando o endpoint de `robots.txt` ficou indisponível. |
| [DFAT, 17/06/2009](https://www.dfat.gov.au/news/media/Pages/australia-s-composition-of-trade-2008) | Japão nº 1 e China nº 2; comércio bilateral de bens e serviços | ano-calendário 2008 | Não | Raw previamente preservado e verificado por SHA-256. Mostra reversão no ano-calendário. |
| [Australian Financial Review, 09/11/2009](https://www.afr.com/markets/china-hits-the-spot-as-trading-partner-20091109-iwhtx) | China nº 1, Japão deslocado; comércio bilateral de bens e serviços | ano fiscal 2008–09; início retrospectivo em 2006–07 | **Sim** | Raw previamente preservado e verificado por SHA-256. A expressão “terceiro ano consecutivo” usa anos fiscais. |
| [DFAT, 30/11/2009](https://www.dfat.gov.au/news/media/Pages/australia-s-composition-of-trade-2008-09) | China nº 1 no comércio bilateral; Japão nº 1 nas exportações | ano fiscal 2008–09 | **Sim** | Raw previamente preservado e verificado por SHA-256. Confirma o último ano fiscal da sequência do AFR. |

## Como interpretar o “terceiro ano” do AFR

O artigo do Australian Financial Review situa o primeiro lugar inicial em
**2006–07** e o dado corrente em **2008–09**. A sequência relevante é,
portanto, 2006–07, 2007–08 e 2008–09. Ela não corresponde a 2006, 2007 e 2008
como anos-calendário. O comunicado do DFAT sobre 2008 reforça essa leitura ao
registrar que o Japão voltou ao primeiro lugar no comércio bilateral daquele
ano-calendário; o comunicado sobre 2008–09 volta a pôr a China em primeiro no
ano fiscal.

## Busca e limites

As consultas combinaram nomes de publicadores, China, Austrália, Japão,
`largest/biggest trading partner`, `second-largest export destination`,
`2006`, `2007`, `2006-07` e títulos conhecidos. Foram pesquisados, entre outros,
ABC, Australian Financial Review, Sydney Morning Herald, The Age, Reserve Bank
of Australia e Department of Foreign Affairs and Trade.

Não foi recuperada nesta rodada uma matéria verificável de 2006–2007 no AFR,
Sydney Morning Herald ou The Age. Esse resultado descreve a cobertura da busca;
ele **não** demonstra ausência de publicação, sobretudo em arquivos pagos ou
incompletamente indexados. Um registro de Hansard do Australian Capital
Territory foi localizado como possível corroboração de 2007, mas não entrou na
tabela porque a navegação interna do PDF falhou.

As consultas executadas, resultados sem recuperação e candidatos excluídos
estão registrados em
`scripts/diagnostics/australia_public_cue_2006_2009_search_log.json`. O log
inclui as URLs do Hansard e do retrospectivo *Trade Through Time*, bem como o
motivo para não tratá-los como evidência-base de datação.

O retrospectivo oficial *Trade Through Time* também não foi usado para datar a
pista: ele é posterior aos eventos e apresenta referências internas divergentes
a 2006 e 2007. A tabela privilegia documentos contemporâneos cuja métrica e base
temporal puderam ser distinguidas.

## Proveniência e reprodução

- Dados documento a documento:
  `data/processed/status_cue_salience/australia_public_cue_media_2006_2009.csv`.
- Cadastro de fontes: `data/processed/status_cue_salience/SOURCES.yaml`.
- Manifesto versionado:
  `scripts/diagnostics/australia_public_cue_2006_2009_manifest.json`.
- Log estruturado da busca:
  `scripts/diagnostics/australia_public_cue_2006_2009_search_log.json`.
- Coletor e validador:
  `scripts/diagnostics/collect_australia_public_cue_2006_2009.py`.
- Execução principal:
  `data/raw/status_cue_salience/AUS/australia_media_search/20260922T160400Z`.
- Integridade dos arquivos sob o diretório raw:
  `data/raw/status_cue_salience/checksums.sha256`.
- Revisão independente final:
  `quality_reports/status_cue_salience/australia_public_cue_2006_2009_independent_review.md`.

Reprodução offline da tabela e das verificações:

```bash
python3 scripts/diagnostics/collect_australia_public_cue_2006_2009.py \
  --build --validate \
  --run-dir data/raw/status_cue_salience/AUS/australia_media_search/20260922T160400Z
```

A validação retornou `PASS`: oito documentos, cinco pistas positivas sob a
métrica ampla de cada fonte, zero fonte estritamente alinhada a exportações de
bens e primeira pista positiva em 2007-05-04. Os arquivos brutos novos da ABC,
respostas de `robots.txt`, metadados e tentativas interrompidas foram preservados
e incluídos no arquivo de checksums. O RBA e o DFAT 2007 permaneceram sem raw do
artigo porque a coleta automatizada parou no controle de robots; as páginas
foram verificadas separadamente no navegador de pesquisa.

Uma revisão independente somente leitura repetiu testes adversariais e aprovou
o fechamento. O validador rejeita mudança do AFR de ano fiscal para
ano-calendário, ID duplicado e alteração de rank, além de recalcular os
marcadores nos raws preservados.

## Implicação operacional

Agentes futuros não devem tratar 2009 como a primeira pista pública **ampla**
da Austrália: há evidência nacional direta em 2007. Também não devem converter
2007 em tratamento goods-only, porque a evidência recuperada se refere a
comércio bilateral agregado. Este trabalho não alterou o manuscrito, o PDF, o
pipeline `targets`, os modelos nem a codificação vigente do tratamento.
