[README.md](https://github.com/user-attachments/files/33515983/README.md)
# Painel Legislativo 2026

Painel interativo das eleições legislativas de 2026 (1º turno, 4 de outubro)
nas 27 unidades da federação: **Senado**, **Câmara dos Deputados** e
**Assembleias Legislativas** (Câmara Legislativa no DF).

**Acesse:** <https://lfbl-cp.github.io/dashboard-legislativo-2026/>

O painel é uma tela só: um mapa em tela cheia que muda conforme os filtros, e
a composição das Casas em hemiciclos no mesmo espaço.

## O que dá para ver

### Mapa

- **Cargos:** Senador, Deputado Federal e Deputado Estadual/Distrital.
- **Escopo:** Brasil inteiro ou uma UF.
- **Unidades:** município, microrregião, mesorregião e UF. Nas 27 capitais,
  também **bairro** e **local de votação**.
- **Agrupar por** partido, federação ou candidato.
- **Modos:**
  - **Quem lidera:** o partido, federação ou candidato mais votado em cada
    unidade, com a folga sobre o 2º colocado.
  - **Desempenho (contínuo):** % dos votos válidos de um partido,
    federação ou candidato em cada unidade.
  - **Clusters (LISA):** Moran local sobre o % dos válidos, com a
    tipologia de territórios eleitorais de Terron (2009): território forte,
    território fraco, forte isolado e fraco isolado.
- **Painel da direita:**
  - ranking dos 10 mais votados do escopo (no Senado, os eleitos primeiro);
  - ou o card do candidato escolhido, com foto, partido, federação,
    situação, votos e redes sociais.
- **Resumo:** comparecimento, válidos, brancos e nulos; o popup de cada
  unidade traz os mais votados.
- **Links compartilháveis:** a visão escolhida fica na URL.

### Composição

Hemiciclos da **Câmara** (513), do **Senado** (81) e das **27 Assembleias**
(1.059 cadeiras), por partido ou federação.

- **Ordem:** os partidos vão da esquerda para a direita pela classificação
  de Bolognesi et al. (2025).
- **Senado:** os 54 eleitos em 2026 mais os 27 eleitos em 2022, pelo partido
  da eleição.
- **Interação:** clicar numa cadeira abre o card do eleito e leva ao
  desempenho dele no mapa.

## Dados

Tudo vem de dados abertos oficiais:

| Fonte | Uso |
|---|---|
| [TSE — Portal de Dados Abertos](https://dadosabertos.tse.jus.br/) | Candidatos, votação por candidato e partido por município/zona, detalhe da votação, votação por seção (capitais), cadastro de locais de votação com coordenadas, fotos dos candidatos |
| [Senado Federal — Dados Abertos](https://www12.senado.leg.br/dados-abertos) | Fotos dos senadores eleitos em 2022 |
| IBGE, via [geobr](https://ipeagit.github.io/geobr/) | Malha municipal 2025, micro e mesorregiões, bairros do Censo 2022 e setores censitários |

Todas as somas são conferidas contra os totais oficiais do TSE. Em todo
município e cargo, os votos dos partidos (nominais + legenda) fecham com os
válidos. Nas capitais, a soma dos locais de votação fecha exatamente com o
resultado do município (comparecimento, válidos, brancos, nulos e cada
partido). Dados pessoais dos candidatos (CPF, e-mail, título) nunca são lidos.

### Escolhas de método

- **Candidatos com dados próprios:**
  - Para deputado, o painel inclui os eleitos, os 3 primeiros suplentes de
    cada lista (partido ou federação), os 10 mais votados de cada UF e de
    cada capital, e o 1º e o 2º colocado de cada unidade do mapa. Isso
    garante que o ranking e o "quem lidera" por candidato sejam exatos.
  - Para senador, entram todos os candidatos.
  - Os totais de partido e federação somam **todos** os candidatos e os
    votos de legenda.
- **Federações:** cada partido conta na federação de 2026 a que pertence.
- **Posição ideológica:** média dos especialistas em 2022 (escala 0–10),
  Tabela 1 de Bolognesi et al. (2025). Partidos renomeados ou fundidos
  seguem as regras dos autores; detalhes em
  [`data-raw/ref/README.md`](data-raw/ref/README.md).
- **LISA:**
  - **Cálculo:** é feito no navegador, replicando `spdep::localmoran`
    (vizinhança queen, pesos padronizados na linha, p < 0,05). Foi conferido
    contra o R em 100% das unidades testadas.
  - **Vizinhança:** cada UF é analisada só com os municípios dela.
- **Bairros nas capitais:**
  - São usados os bairros do IBGE (Censo 2022). Onde o IBGE não tem bairro,
    São Paulo usa os 96 distritos, Brasília as 33 Regiões Administrativas e
    Goiânia as unidades territoriais de planejamento.
  - Rio Branco, São Luís e Palmas aparecem só com locais de votação.
  - Locais sem coordenada ou fora de todos os bairros entram apenas no
    resumo da capital.

## Como rodar

Requer R ≥ 4.6 com `data.table`, `sf`, `geobr`, `rmapshaper`, `geojsonio`,
`spdep`, `jsonlite`, `httr`, `readxl` e `magick`. As versões usadas estão em
[`renv.lock`](renv.lock).

```sh
Rscript pipeline/run_pipeline.R                     # pipeline completo
Rscript pipeline/run_pipeline.R --etapa=exportar    # uma etapa (ou várias, separadas por vírgula)
Rscript -e "testthat::test_dir('tests/testthat')"   # testes
Rscript -e "servr::httd('.', port = 8000)"          # site local em http://localhost:8000/frontend/
```

**Etapas, na ordem:**

| Etapa | O que faz |
|---|---|
| `candidatos` | Lê e valida os candidatos |
| `geografia` | Monta a malha e as regiões |
| `votos` | Soma os votos e define quais candidatos são exibidos |
| `fotos` | Baixa e recorta as fotos dos candidatos exibidos |
| `composicao` | Gera os hemiciclos |
| `exportar` | Gera os JSON por UF |
| `capitais` | Gera bairros e locais de votação |

Os arquivos brutos do TSE (~3 GB) são baixados para `data/raw/`, que não é
versionado. O site é estático (HTML, CSS e JavaScript, com Leaflet e
topojson-client) e serve o conteúdo de `output/`.

```
R/              funções do pipeline, uma etapa por arquivo
pipeline/       orquestração (run_pipeline.R)
data-raw/ref/   tabelas de referência: partidos, federações, municípios
output/         dados publicados: JSON, TopoJSON e fotos
frontend/       site estático
tests/          testes (testthat) e QA do site no Chrome headless
```

## Referências

- BOLOGNESI, Bruno; RIBEIRO, Ednaldo; CODATO, Adriano; SILVA, Bruno Fernando
  da. O desaparecimento do centro ideológico no sistema partidário
  brasileiro: a classificação mais atualizada dos experts. *Opinião
  Pública*, Campinas, v. 31, e31120, 2025.
- TERRON, Sonia Luiza. *A composição de territórios eleitorais no Brasil:
  uma análise das votações de Lula (1989-2006)*. Tese (Doutorado em Ciência
  Política) — Instituto Universitário de Pesquisas do Rio de Janeiro
  (IUPERJ), Rio de Janeiro, 2009.
- ANSELIN, Luc. Local Indicators of Spatial Association — LISA.
  *Geographical Analysis*, v. 27, n. 2, p. 93–115, 1995.

## Autor

Luiz Felipe Bezerra Lopes
