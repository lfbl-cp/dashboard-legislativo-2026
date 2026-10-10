# Painel Legislativo 2026 — CLAUDE.md

## Propósito

Painel público e interativo das eleições legislativas de 2026 (1º turno,
04/10/2026) nas 27 UFs: Senador, Deputado Federal e Deputado Estadual
(Distrital no DF), com resultado por município e hemiciclos da composição
por partido/federação (Câmara, Senado e as 27 Assembleias). Plano de fases e
decisões em `PLANO.md`.

Combina dois projetos anteriores do usuário:
- **Dados/regras**: `C:\Users\felip\Documents\Dashboard Pernambuco 2026`
  (pipeline R sobre TSE 2026, partidos/federações, eleitos/suplentes, fotos,
  LISA no navegador via `www/lisa.js`). Saída lá é um HTML único -- não
  escala para 27 UFs, não copiar esse formato.
- **Visual/arquitetura de site**: `painel-eleicoes-2026/` (clone, fora do
  git, só referência; tem seu próprio `CLAUDE.md` com muitas lições de
  front-end e geo -- vale ler antes das Fases 3-4).

## Decisões fixas (do usuário)

- **Uma tela só: um único mapa em tela cheia que muda conforme os filtros**
  do painel flutuante (igual ao clone). Nunca várias seções/mapas com scroll
  como no painel de PE. O hemiciclo ocupa o mesmo espaço (troca de
  visualização), não é seção extra.
- Só cargos legislativos (sem Presidente/Governador, sem 2º turno).
- Deputados: dados por candidato **só de eleitos e suplentes**; senador,
  todos. Totais de partido/federação somam **todos os candidatos + legenda**
  (calculado no pipeline, exportado só como total).
- Senado no hemiciclo: 81 cadeiras = 54 eleitos em 2026 + 27 eleitos em
  2022, **pelo partido da eleição** (não partido atual nem suplente em
  exercício).
- Ordem no hemiciclo: esquerda→direita pela classificação de **Bolognesi
  et al.** (Opinião Pública, 2025, média 2022) -- ver
  `data-raw/ref/README.md` para fonte e regras de renomeação/fusão.
- Modo federação: cada partido vai para a federação **de 2026** a que
  pertence (inclusive senadores de 2022).
- Geografia: município + micro/meso/UF; bairros e locais de votação numa
  fase posterior.
- Recursos trazidos do painel de PE: fotos + card do candidato.

## Estrutura

```
R/                 funções, uma etapa por arquivo numerado; só definem
                   funções, nunca rodam nada ao dar source()
pipeline/          run_pipeline.R -- orquestração (--etapa=...)
data-raw/ref/      tabelas de referência editadas à mão (partidos, federações,
                   linkador de municípios) -- ver README lá
data/raw/          ZIPs/CSVs do TSE (cache, gitignored)
data/processed/    rds intermediários (gitignored)
output/            o que o site serve (versionado): fotos/, depois JSON/TopoJSON
frontend/          HTML/CSS/JS estático (Fase 2+)
tests/testthat/    testes
```

## Comandos

```
Rscript pipeline/run_pipeline.R                        # tudo
Rscript pipeline/run_pipeline.R --etapa=candidatos     # uma etapa
Rscript -e "testthat::test_dir('tests/testthat')"      # testes (da raiz)
Rscript tests/qa_frontend.R [pasta]                    # QA do front no Chrome headless
Rscript -e "servr::httd('.', port = 8000)"             # servidor local -> /frontend/
```

`file://` não funciona (o `fetch` de `../output/` é bloqueado). Não há
Python nem Node na máquina; servidor e QA são em R (`servr`, `chromote`).
No QA, o servidor roda num processo à parte (`processx`): o `servr` em modo
daemon depende do loop de eventos da sessão, que o `chromote` bloqueia
(`Page.navigate` estoura o tempo). Para o `chromote` achar o navegador:
`CHROMOTE_CHROME="C:/Program Files/Google/Chrome/Application/chrome.exe"`.

R 4.6.1 (`C:\Program Files\R\R-4.6.1`), pacotes na biblioteca do usuário.
`renv.lock` só **registra** as versões (snapshot da biblioteca do usuário);
o projeto não ativa biblioteca renv própria (sem `.Rprofile`) -- o clone
documenta várias dores de binário Windows com renv; evitar até precisar.

## Dados do TSE -- o que já se sabe

- CDN `cdn.tse.jus.br/estatistica/sead/...` exige User-Agent de navegador
  (403 sem). Funcionando em out/2026 (sem bloqueio de defeso).
- `consulta_cand_{ano}.zip`: um CSV por UF + `_BR` (Presidente) + `_BRASIL`
  (concatenação, não usar). Traz CPF, e-mail e título de eleitor -- o
  pipeline lê só `COLUNAS_CANDIDATO` (`R/03_candidatos.R`), dado pessoal
  nunca entra. `SQ_CANDIDATO` sempre como texto (não cabe em int32).
- `DS_SIT_TOT_TURNO` 2026: ELEITO (senador), ELEITO POR QP, ELEITO POR
  MÉDIA, SUPLENTE, NÃO ELEITO, ausente (sem totalização). Deputado Distrital
  é CD_CARGO 8, tratado como "estadual".
- Partido é chaveado por **sigla**, não número (o 20 era PSC em 2022, é PODE
  em 2026). PSC só existe nos dados por causa de Cleitinho (MG, Senado 2022).
- Fotos: `foto_cand{ano}_{UF}_div.zip`, arquivos `F{UF}{SQ}_div.jpg` (161x225).
  Os de 2022 somam ~770 MB para só 27 fotos -- não usados: os senadores de
  2022 vêm da API de dados abertos do Senado (`senador/lista/legislatura/57`,
  titular com mandato iniciado na 57ª, 1 por UF, casado por UF e conferido
  por nome no log), recortados para 161x225 com `magick`.
- `votacao_candidato_munzona_2026.zip`: 445 MB (Fase 3).

## Estado atual

- **Fase 0 (bootstrap)** completa: git (`main`), estrutura, `.gitignore`,
  `renv.lock`, referências.
- **Fase 1 (candidatos nacional)** completa: etapas `candidatos` e `fotos`.
  Validado: Câmara 513, Senado 81 (2 de 2026 + 1 de 2022 em cada UF), 27
  Assembleias com o tamanho constitucional (CF art. 27, total 1.059);
  13.058 exibidos, 13.057 com foto (71 MB em `output/fotos/`; o único sem
  foto é candidatura ao Senado sem totalização, sem foto no TSE); 15 testes
  passando. MISSÃO (fora da pesquisa) posicionado junto ao NOVO por decisão
  do usuário (`metodo_ideologia = estimado`).
- **Fase 2 (hemiciclos)** completa:
  - Etapa `composicao` -> `output/composicao.json` (29 Casas, 1.653
    cadeiras, ~710 KB; metade disso são links de redes sociais -- ver
    pendência de economia de dados abaixo). Redes normalizadas na origem
    (`limpar_url_rede()`: minúsculas, sem query de rastreamento, até 6,
    redes conhecidas primeiro). Coligação "FEDERAÇÃO" do TSE vira vazio.
  - Front-end (`frontend/`): abas Mapa | Composição; o hemiciclo ocupa o
    lugar do mapa. `hemiciclo.js` = layout próprio (arcos concêntricos,
    busca binária do espaçamento, cadeiras por fileira proporcionais ao
    arco, ordenadas por ângulo e preenchidas na ordem dos grupos).
    `composicao.js` = Casa/UF, destaque de bancada (Câmara/Senado; legenda
    passa a contar só a bancada), Partido|Federação, clique na legenda
    destaca o grupo, clique na cadeira abre card (foto, partido,
    federação, situação, dados, redes), tooltip no hover. Senado: cadeira
    vazada = eleito em 2022. Estado na URL
    (`#aba=composicao&casa=assembleia&uf=PE&agrupar=federacao`).
  - Mapa-base claro trocado de OSM para Esri World Light Gray (a política
    de uso dos tiles do OSM não admite tráfego alto -- ver clone).
  - Mapa ainda só com mapa-base (Fase 4); aba padrão é Composição.
  - Verificado com `tests/qa_frontend.R`: 11 cenários sem erro de JS/HTTP,
    contagem de cadeiras = tamanho da Casa em todos, 27 vazadas no Senado,
    card e tooltip funcionando; capturas conferidas visualmente (desktop
    escuro/claro, celular 390px).
- **Pendente (pedido do usuário)**: discutir economia de dados do projeto
  (fotos 71 MB no repo, redes no composicao.json, formato dos dados de
  votação da Fase 3) antes de seguir para a Fase 3.
