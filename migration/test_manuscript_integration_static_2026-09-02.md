# Teste estático da integração do manuscrito — 2026-09-02

## Comando

```sh
Rscript --vanilla migration/test_manuscript_integration_static.R
```

## Resultado

**PASS** — `ALL_STATIC_MANUSCRIPT_INTEGRATION_TESTS_PASSED`.

Foram confirmados:

- parsing de `_targets.R`, dos três scripts R alterados/adicionados e de todos os
  chunks de `paper_v4.Rmd` extraídos com `knitr::purl()`;
- permanência do manifesto de 27 folhas e ausência de todos os basenames legados no
  manuscrito;
- ausência de `readr::read_csv()` no manuscrito;
- mapeamento dos 12 objetos SDiD Brasil, da tabela de commodity e dos nove objetos
  UNGA-DM para targets em memória;
- consumo das cinco figuras migradas por file targets;
- substituição consistente dos alvos cross-country antigos pelos alvos full-union;
- declaração dos quatro novos alvos de integração e do novo arquivo de funções;
- parametrização explícita do script de dose–resposta;
- classificação, em fixture, de tratado qualificante, controle nunca China-top,
  ausência de ranking comercial, curta duração, entrada pré-2000 e ausência de ano
  anterior limpo;
- falha fechada da figura dinâmica diante de horizonte duplicado, denominador
  incompatível e ATT agregado não reproduzido;
- falha fechada do wrapper de dose–resposta diante de extensões de saída inválidas,
  sem invocar `Rscript`;
- publicação transacional dos dois artefatos com e sem arquivos finais prévios;
- rollback integral quando a segunda movimentação falha, inclusive no estado misto
  em que somente um output existia;
- rejeição anterior à publicação de diretórios, links simbólicos válidos ou quebrados,
  aliases, colisões entre staged e outputs, containers inválidos e caminhos `NA`;
- remoção verificada dos backups depois de sucesso e rollback e preservação dos
  backups quando uma falha injetada impede o próprio rollback;
- detecção por tamanho e MD5 de corrupção injetada depois da movimentação, com
  rollback integral;
- rejeição de FIFO antes da cópia e relato explícito de backup residual quando a
  criação parcial de backups e a limpeza falham simultaneamente;
- store configurado localmente, DAG acíclico e ancestralidade explícita dos inputs,
  gates, scripts e file targets novos.

Os avisos de locale `C` e de pacotes compilados sob R 4.4.3 são informativos e não
alteraram o resultado.

Nenhum target foi materializado. Nenhum coletor, acesso à rede, modelo, placebo,
bootstrap, writer de figura de produção, renderização do R Markdown ou inspeção do PDF
foi executado.
