# Scripts do piloto de acervos jornalísticos

Este diretório implementa o piloto pré-especificado de cinco veículos por quatro datas. A coleta e as transformações são deliberadamente separadas: `collect.py` faz somente requisições e preserva respostas; `process.py` lê exclusivamente os brutos salvos; `validate.py` reconstrói os outputs em diretório temporário sem repetir downloads.

## Dependências

- Python 3.11 ou posterior;
- pacotes em `requirements.txt` (`requests` e `lxml`);
- opcionalmente, Google Chrome/Chromium já instalado para o segundo diagnóstico do mbl.is. A indisponibilidade do navegador é registrada como falha do probe, sem instalação automática.

Instalação sugerida em ambiente virtual:

```bash
python3 -m venv .venv-media-archive-pilot
. .venv-media-archive-pilot/bin/activate
python -m pip install -r scripts/diagnostics/media_archive_pilot/requirements.txt
```

## Arquivos e ordem de execução

1. `pilot_config.json`: fixa execução, datas, cinco fontes, limites HTTP e dicionários de menções.
2. `collect.py`: verifica a pré-especificação temporal, consulta `robots.txt` e a página de condições/entrada de cada fonte, aplica no máximo duas tentativas apenas a falhas transitórias, pausa um segundo entre requisições e grava respostas sob `data/raw/`.
3. `probe_mbl_headless.py`: segundo mecanismo automatizado e delimitado para o mbl.is; não resolve challenges e não alimenta `records.csv`.
4. `process.py`: extrai metadados, marca datas inferidas, aplica dicionários somente a `title_original`, sinaliza duplicatas sem eliminar matérias distintas com títulos iguais e produz os diagnósticos.
5. `validate.py`: valida esquema e 20 combinações, reconcilia contagens, reexecuta as regras de deduplicação, confere uma amostra contra os brutos e comprova processamento byte a byte sem rede.
6. `build_manifest.py`: deve ser executado por último, depois do README de resultados, para gerar checksums de todos os artefatos do piloto.

Para uma nova execução, copie o diretório do piloto ou atualize conscientemente `run_date` e a quarta data no arquivo de configuração. O coletor se recusa a sobrescrever um diretório bruto já iniciado ou concluído. Para reproduzir apenas o processamento de 2026-09-14, use:

```bash
python3 scripts/diagnostics/media_archive_pilot/process.py \
  --raw-dir data/raw/media_archive_pilot/2026-09-14 \
  --output-dir /tmp/media_archive_pilot_reprocess \
  --report-dir quality_reports/media_archive_pilot
```

Não se deve usar o script completo para “atualizar” a coleta de 2026-09-14: os brutos são imutáveis. O escopo não inclui corpo das matérias, tradução, classificação temática, OCR, autenticação, assinatura, obtenção de credenciais ou qualquer período além das quatro datas fixas.
