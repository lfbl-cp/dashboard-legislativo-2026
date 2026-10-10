# =============================================================================
# Constantes do pipeline. Só define objetos; nunca roda nada ao dar source().
# =============================================================================

ANO <- 2026
TURNO <- 1
DATA_ELEICAO <- as.Date("2026-10-04")

# Senado: 2026 renova 2/3 (2 vagas por UF). O 1/3 restante foi eleito em
# 2022 (1 vaga por UF) e segue no mandato até 2031 -- entra no hemiciclo pelo
# partido da eleição.
ANO_SENADO_ANTERIOR <- 2022
# Legislatura que começou com os senadores eleitos em ANO_SENADO_ANTERIOR
# (57ª: 2023-2027) -- usada para achar as fotos na API do Senado.
LEGISLATURA_SENADO_ANTERIOR <- 57

UFS_BRASIL <- c("AC", "AL", "AM", "AP", "BA", "CE", "DF", "ES", "GO", "MA", "MG",
                "MS", "MT", "PA", "PB", "PE", "PI", "PR", "RJ", "RN", "RO", "RR",
                "RS", "SC", "SE", "SP", "TO")

NOMES_UF <- c(
  AC = "Acre", AL = "Alagoas", AM = "Amazonas", AP = "Amapá", BA = "Bahia",
  CE = "Ceará", DF = "Distrito Federal", ES = "Espírito Santo", GO = "Goiás",
  MA = "Maranhão", MG = "Minas Gerais", MS = "Mato Grosso do Sul",
  MT = "Mato Grosso", PA = "Pará", PB = "Paraíba", PE = "Pernambuco",
  PI = "Piauí", PR = "Paraná", RJ = "Rio de Janeiro", RN = "Rio Grande do Norte",
  RO = "Rondônia", RR = "Roraima", RS = "Rio Grande do Sul",
  SC = "Santa Catarina", SE = "Sergipe", SP = "São Paulo", TO = "Tocantins"
)

# Cargos do painel (CD_CARGO do TSE). Deputado Distrital (DF) é tratado como
# "estadual": mesma posição na estrutura, só muda o nome da Casa.
CARGOS <- data.frame(
  cd_cargo = c(5L, 6L, 7L, 8L),
  ds_cargo = c("SENADOR", "DEPUTADO FEDERAL", "DEPUTADO ESTADUAL", "DEPUTADO DISTRITAL"),
  id       = c("senador", "federal", "estadual", "estadual"),
  tipo     = c("majoritario", "proporcional", "proporcional", "proporcional"),
  stringsAsFactors = FALSE
)

# Casas legislativas do aba Composição.
CASAS <- c(camara = "Câmara dos Deputados", senado = "Senado Federal")
nome_assembleia <- function(uf) {
  if (uf == "DF") "Câmara Legislativa do Distrito Federal" else
    paste("Assembleia Legislativa —", NOMES_UF[[uf]])
}

# --- fontes (dados abertos do TSE) ---------------------------------------------
URL_TSE <- "https://cdn.tse.jus.br/estatistica/sead"
url_consulta_cand <- function(ano) sprintf("%s/odsele/consulta_cand/consulta_cand_%d.zip", URL_TSE, ano)
url_rede_social   <- function(ano) sprintf("%s/odsele/consulta_cand/rede_social_candidato_%d.zip", URL_TSE, ano)
url_fotos         <- function(ano, uf) sprintf("%s/eleicoes/eleicoes%d/fotos/foto_cand%d_%s_div.zip", URL_TSE, ano, ano, uf)
url_senado_legislatura <- function(n) sprintf("https://legis.senado.leg.br/dadosabertos/senador/lista/legislatura/%d.json", n)
url_partido_munzona <- function(ano) sprintf("%s/odsele/votacao_partido_munzona/votacao_partido_munzona_%d.zip", URL_TSE, ano)
url_detalhe_munzona <- function(ano) sprintf("%s/odsele/detalhe_votacao_munzona/detalhe_votacao_munzona_%d.zip", URL_TSE, ano)
url_munzona       <- function(ano) sprintf("%s/odsele/votacao_candidato_munzona/votacao_candidato_munzona_%d.zip", URL_TSE, ano)
url_votacao_secao <- function(ano, uf) sprintf("%s/odsele/votacao_secao/votacao_secao_%d_%s.zip", URL_TSE, ano, uf)
url_locais        <- function(ano) sprintf("%s/odsele/eleitorado_locais_votacao/eleitorado_local_votacao_%d.zip", URL_TSE, ano)

# Capitais (código IBGE) -- piloto de bairros e locais de votação (Fase 5).
CAPITAIS <- c(
  AC = 1200401L, AL = 2704302L, AM = 1302603L, AP = 1600303L, BA = 2927408L,
  CE = 2304400L, DF = 5300108L, ES = 3205309L, GO = 5208707L, MA = 2111300L,
  MG = 3106200L, MS = 5002704L, MT = 5103403L, PA = 1501402L, PB = 2507507L,
  PE = 2611606L, PI = 2211001L, PR = 4106902L, RJ = 3304557L, RN = 2408102L,
  RO = 1100205L, RR = 1400100L, RS = 4314902L, SC = 4205407L, SE = 2800308L,
  SP = 3550308L, TO = 1721000L
)

# O CDN do TSE devolve 403 sem User-Agent de navegador.
UA_NAVEGADOR <- "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"

# --- caminhos --------------------------------------------------------------------
DIR_RAW       <- "data/raw"
DIR_PROCESSED <- "data/processed"
DIR_REF       <- "data-raw/ref"
DIR_OUTPUT    <- "output"
