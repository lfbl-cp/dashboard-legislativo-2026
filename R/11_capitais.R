# =============================================================================
# Bairros e locais de votação -- piloto nas 27 capitais (Fase 5).
#
# Fontes do TSE:
#   votacao_secao_{ano}_{UF}   votos por seção x votável (granularidade mais
#                              fina). Só a capital é lida: o CSV da UF é
#                              varrido em blocos e só as linhas do município
#                              são parseadas (o de SP tem ~6 GB).
#   eleitorado_local_votacao   cadastro dos locais: nome, endereço, bairro
#                              declarado, eleitores e NR_LATITUDE/LONGITUDE
#                              oficiais (desde 2022).
#
# Regras dos votos (iguais às do painel de PE):
#   SQ_CANDIDATO > 0   nominal -> partido do candidato (consulta_cand)
#   SQ_CANDIDATO = -3  legenda -> NR_VOTAVEL = número do partido
#   NR_VOTAVEL 95/96   branco/nulo
# Voto nominal de candidato (ou legenda de partido) sem voto válido no munzona
# do município é voto anulado (candidatura indeferida): fica fora de válidos
# e nulos, como na totalização, e só entra no comparecimento.
#
# Subdivisões (polígonos) da capital: bairros do IBGE (Censo 2022). Seis
# capitais não têm bairro na malha do IBGE; três delas usam a divisão
# intramunicipal dos setores censitários de 2022 (ver SUBDIVISOES_SETOR) e
# Rio Branco, São Luís e Palmas ficam só com locais de votação.
#
# Saída (carregada só quando a capital é escolhida no mapa):
#   output/capitais/{UF}.json        locais (colunar) + votos inteiros por
#                                    local, no mesmo formato de votos/{UF}.json
#                                    (vetores densos por partido, pares
#                                    esparsos por candidato exibido), índice
#                                    local -> subdivisão e vizinhança queen
#                                    das subdivisões (LISA no navegador)
#   output/geo/subdivisoes_{UF}.topojson
# =============================================================================

# Divisões dos setores censitários de 2022 usadas onde o IBGE não tem bairro.
SUBDIVISOES_SETOR <- list(
  SP = list(nivel = "district", rotulo = "Distritos", singular = "Distrito"),
  DF = list(nivel = "subdistrict", rotulo = "Regiões administrativas", singular = "Região administrativa"),
  GO = list(nivel = "subdistrict", rotulo = "Unidades territoriais", singular = "Unidade territorial")
)
SUBDIVISAO_BAIRRO <- list(rotulo = "Bairros", singular = "Bairro")
KEEP_SUBDIVISAO <- 0.3
TOLERANCIA_MUNICIPIO_M <- 1000 # ponto além disso fora do próprio município = coordenada errada

# --- votos por seção ---------------------------------------------------------------

# Linhas da capital no votacao_secao da UF, somadas por local x votável.
# O CSV é varrido em blocos de linhas e só as que trazem o código TSE do
# município (";<código>;\"", que precede NM_MUNICIPIO) vão para o fread;
# o filtro exato por coluna vem depois (o padrão pode casar NR_VOTAVEL).
ler_secao_capital <- function(uf, cd_tse, ano = ANO) {
  zip <- obter_zip_tse(url_votacao_secao(ano, uf))
  csv <- sprintf("votacao_secao_%d_%s.csv", ano, uf)
  tmp <- tempfile("secao_")
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  utils::unzip(zip, files = csv, exdir = tmp)

  con <- file(file.path(tmp, csv), open = "rb")
  cabecalho <- readLines(con, n = 1, warn = FALSE)
  padrao <- sprintf(";%d;\"", cd_tse)
  partes <- list()
  repeat {
    l <- readLines(con, n = 2e6, warn = FALSE)
    if (length(l) == 0) break
    partes[[length(partes) + 1]] <- l[grepl(padrao, l, fixed = TRUE, useBytes = TRUE)]
  }
  close(con)

  col <- c("NR_TURNO", "CD_MUNICIPIO", "NR_ZONA", "NR_SECAO", "CD_CARGO", "NR_VOTAVEL",
           "QT_VOTOS", "NR_LOCAL_VOTACAO", "SQ_CANDIDATO")
  x <- data.table::fread(text = c(cabecalho, unlist(partes)), sep = ";", quote = "\"",
                         select = col, integer64 = "character", showProgress = FALSE,
                         colClasses = list(character = "SQ_CANDIDATO"))
  x <- x[CD_MUNICIPIO == cd_tse & NR_TURNO == TURNO & CD_CARGO %in% CARGOS$cd_cargo]
  if (nrow(x) == 0) stop(sprintf("Nenhuma linha da capital %s (TSE %d) no votacao_secao", uf, cd_tse))
  secoes <- x[, .(secoes = data.table::uniqueN(NR_SECAO)), by = .(nr_zona = NR_ZONA, nr_local = NR_LOCAL_VOTACAO)]
  v <- x[, .(votos = sum(QT_VOTOS)),
         by = .(nr_zona = NR_ZONA, nr_local = NR_LOCAL_VOTACAO, cd_cargo = CD_CARGO,
                sq_candidato = SQ_CANDIDATO, nr_votavel = NR_VOTAVEL)]
  list(votos = v, secoes = secoes)
}

# Com cache em data/processed/capitais/ (a varredura de SP leva minutos).
obter_secao_capital <- function(uf, cd_tse, ano = ANO) {
  pasta <- file.path(DIR_PROCESSED, "capitais")
  dir.create(pasta, showWarnings = FALSE, recursive = TRUE)
  cache <- file.path(pasta, sprintf("secao_%d_%s.rds", ano, uf))
  if (file.exists(cache)) return(readRDS(cache))
  message(sprintf("  seções %s ...", uf))
  x <- ler_secao_capital(uf, cd_tse, ano)
  saveRDS(x, cache)
  x
}

# Classifica os votos de um local x votável: tipo (nominal / legenda /
# branco / nulo), cargo do painel e sigla do partido.
classificar_votos_secao <- function(v, candidatos, partidos, validos_munzona) {
  v <- data.table::copy(v)
  v[, cargo := CARGOS$id[match(cd_cargo, CARGOS$cd_cargo)]]
  v[, tipo := data.table::fcase(nr_votavel == 95L, "branco", nr_votavel == 96L, "nulo",
                                sq_candidato == "-3", "legenda", default = "nominal")]
  cand <- candidatos[candidatos$ano == ANO, ]
  v[tipo == "nominal", sigla := cand$sigla[match(sq_candidato, cand$sq_candidato)]]
  v[tipo == "legenda", sigla := partidos$sigla[match(nr_votavel, partidos$nr_2026)]]
  sem <- v[tipo %in% c("nominal", "legenda") & is.na(sigla)]
  if (nrow(sem) > 0) {
    stop(sprintf("Voto sem partido identificado (%d linha(s)), ex. cargo %d votável %d sq %s",
                 nrow(sem), sem$cd_cargo[1], sem$nr_votavel[1], sem$sq_candidato[1]))
  }
  # Nominal de candidato sem voto válido no município, como na totalização:
  #   - ausente do munzona do município (candidatura já inapta na eleição):
  #     nulo técnico, que o TSE soma aos nulos (QT_TOTAL_VOTOS_NULOS);
  #   - presente com 0 voto válido: anulado sub judice, nem válido nem nulo.
  # Legenda de partido sem voto válido no cargo: anulada sub judice se o
  # munzona por partido registra legenda anulada sub judice dele no
  # município (QT_VOTOS_LEGENDA_ANUL_SUBJUD), senão nulo técnico.
  nominal_invalido <- v$tipo == "nominal" & !(v$sq_candidato %in% validos_munzona$candidatos)
  tecnico_nom <- nominal_invalido & !(v$sq_candidato %in% validos_munzona$presentes)
  legenda_invalida <- v$tipo == "legenda" & !(paste(v$cargo, v$sigla) %in% validos_munzona$partidos)
  legenda_subjud <- paste(v$cargo, v$sigla) %in% validos_munzona$legenda_subjud
  tecnico <- tecnico_nom | (legenda_invalida & !legenda_subjud)
  anulado <- (nominal_invalido & !tecnico_nom) | (legenda_invalida & legenda_subjud)
  v[tecnico, `:=`(tipo = "nulo", sigla = NA_character_)]
  v[anulado, `:=`(tipo = "anulado", sigla = NA_character_)]
  v
}

# Quem tem voto válido no município segundo o munzona: candidatos (sq),
# candidatos presentes (mesmo com 0 válido), partidos com voto válido e
# partidos com legenda anulada sub judice ("cargo sigla", do munzona por
# partido).
validos_munzona_capital <- function(uf, cd_tse, votos_municipio, ano = ANO) {
  zip <- obter_zip_tse(url_partido_munzona(ano))
  p <- ler_csv_do_zip(zip, sprintf("votacao_partido_munzona_%d_%s.csv", ano, uf),
                      c("NR_TURNO", "CD_MUNICIPIO", "CD_CARGO", "SG_PARTIDO", "QT_TOTAL_VOTOS_LEG_VALIDOS",
                        "QT_VOTOS_NOMINAIS_VALIDOS", "QT_VOTOS_LEGENDA_ANUL_SUBJUD"))
  p <- p[NR_TURNO == TURNO & as.integer(CD_MUNICIPIO) == cd_tse & CD_CARGO %in% CARGOS$cd_cargo]
  p[, cargo := CARGOS$id[match(CD_CARGO, CARGOS$cd_cargo)]]
  p <- p[, .(validos = sum(QT_TOTAL_VOTOS_LEG_VALIDOS + QT_VOTOS_NOMINAIS_VALIDOS),
             subjud = sum(QT_VOTOS_LEGENDA_ANUL_SUBJUD)), by = .(cargo, SG_PARTIDO)]
  m <- votos_municipio[votos_municipio$uf == uf & votos_municipio$cd_municipio_tse == cd_tse]
  list(candidatos = m$sq_candidato[m$votos > 0], presentes = m$sq_candidato,
       partidos = p[validos > 0, paste(cargo, SG_PARTIDO)],
       legenda_subjud = p[subjud > 0, paste(cargo, SG_PARTIDO)])
}

# --- locais de votação --------------------------------------------------------------

# Cadastro dos locais da capital: um registro por (zona, local), também pelo
# número ORIGINAL (local renumerado/agregado entre o cadastro e a votação --
# em 2026 o TSE agregou seções).
ler_locais_capital <- function(uf, cd_tse, ano = ANO) {
  zip <- obter_zip_tse(url_locais(ano))
  col <- c("NR_TURNO", "CD_MUNICIPIO", "NR_ZONA", "NR_SECAO", "NR_LOCAL_VOTACAO", "NM_LOCAL_VOTACAO",
           "DS_ENDERECO", "NM_BAIRRO", "NR_LATITUDE", "NR_LONGITUDE", "QT_ELEITOR_SECAO",
           "NR_LOCAL_VOTACAO_ORIGINAL")
  x <- ler_csv_do_zip(zip, sprintf("eleitorado_local_votacao_%d_%s.csv", ano, uf), col)
  x <- x[as.integer(CD_MUNICIPIO) == cd_tse & NR_TURNO == TURNO]
  num <- function(s) suppressWarnings(as.numeric(sub(",", ".", s, fixed = TRUE)))
  x[, `:=`(lat = num(NR_LATITUDE), lon = num(NR_LONGITUDE))]
  x[is.na(lat) | is.na(lon) | lat %in% c(-1, 0) | lon %in% c(-1, 0) | abs(lat) > 90 | abs(lon) > 180,
    `:=`(lat = NA_real_, lon = NA_real_)]
  resumir <- function(d, nr) {
    d[, .(nome = NM_LOCAL_VOTACAO[1], endereco = DS_ENDERECO[1], bairro_tse = NM_BAIRRO[1],
          lat = stats::na.omit(lat)[1], lon = stats::na.omit(lon)[1],
          eleitores = sum(QT_ELEITOR_SECAO, na.rm = TRUE)),
      by = .(nr_zona = NR_ZONA, nr_local = d[[nr]])]
  }
  atual <- resumir(x, "NR_LOCAL_VOTACAO")
  orig <- resumir(x[!is.na(NR_LOCAL_VOTACAO_ORIGINAL) & NR_LOCAL_VOTACAO_ORIGINAL > 0], "NR_LOCAL_VOTACAO_ORIGINAL")
  orig <- orig[!paste(nr_zona, nr_local) %in% paste(atual$nr_zona, atual$nr_local)]
  list(atual = atual, original = orig)
}

# Locais que aparecem nos votos, com nome/coordenada do cadastro.
montar_locais <- function(secoes, cadastro) {
  l <- data.table::copy(secoes)
  l[, chave := paste(nr_zona, nr_local)]
  casar <- function(cad) cad[match(l$chave, paste(cad$nr_zona, cad$nr_local))]
  a <- casar(cadastro$atual)
  o <- casar(cadastro$original)
  for (col in c("nome", "endereco", "bairro_tse", "lat", "lon", "eleitores")) {
    data.table::set(l, j = col, value = data.table::fcoalesce(a[[col]], o[[col]]))
  }
  l[, casou := data.table::fifelse(!is.na(a$nome), "atual", data.table::fifelse(!is.na(o$nome), "original", NA_character_))]
  l[is.na(eleitores), eleitores := 0L]
  data.table::setorder(l, nr_zona, nr_local)
  l
}

# Descarta coordenada a mais de TOLERANCIA_MUNICIPIO_M do próprio município
# (geometria completa do IBGE). Devolve os locais com `coord_descartada`.
conferir_coordenadas <- function(locais, municipio_sf) {
  locais$coord_descartada <- FALSE
  tem <- which(!is.na(locais$lat))
  if (length(tem) == 0) return(locais)
  pts <- sf::st_as_sf(locais[tem], coords = c("lon", "lat"), crs = 4326)
  mun <- sf::st_transform(sf::st_geometry(municipio_sf), sf::st_crs(pts))
  sf::sf_use_s2(TRUE)
  d <- as.numeric(sf::st_distance(pts, mun))
  ruim <- tem[d > TOLERANCIA_MUNICIPIO_M]
  if (length(ruim) > 0) {
    locais$coord_descartada[ruim] <- TRUE
    locais$lat[ruim] <- NA_real_
    locais$lon[ruim] <- NA_real_
  }
  locais
}

# --- subdivisões (bairros / distritos / RAs) ----------------------------------------

# sf das subdivisões da capital (geometria completa), com `nome`, ordenado
# por nome; NULL se a capital não tem subdivisão na malha do IBGE. Também
# devolve os rótulos (plural/singular) para o front-end.
montar_subdivisoes <- function(uf) {
  code <- CAPITAIS[[uf]]
  sf::sf_use_s2(FALSE)
  on.exit(sf::sf_use_s2(TRUE), add = TRUE)
  if (uf %in% names(SUBDIVISOES_SETOR)) {
    cfg <- SUBDIVISOES_SETOR[[uf]]
    setores <- ler_geobr_cache(sprintf("setores_2022_%d", code), function() {
      geobr::read_census_tract(code_tract = code, year = 2022, simplified = FALSE, showProgress = FALSE)
    })
    cod <- setores[[paste0("code_", cfg$nivel)]]
    nome <- setores[[paste0("name_", cfg$nivel)]]
    rotulos <- cfg[c("rotulo", "singular")]
  } else {
    bairros <- ler_geobr_cache("bairros_br_2022", function() {
      geobr::read_neighborhood(year = 2022, showProgress = FALSE)
    })
    setores <- bairros[as.integer(bairros$code_muni) == code, ]
    if (nrow(setores) == 0) return(NULL)
    cod <- setores$code_neighborhood
    nome <- setores$name_neighborhood
    rotulos <- SUBDIVISAO_BAIRRO
  }
  # Une as partes de cada subdivisão (setores, ou bairro em várias linhas).
  g <- sf::st_make_valid(sf::st_geometry(setores))
  grupos <- split(seq_along(cod), cod)
  geom <- suppressMessages(do.call(c, lapply(grupos, function(i) sf::st_union(g[i]))))
  out <- sf::st_sf(codigo = names(grupos), nome = nome[vapply(grupos, `[`, integer(1), 1)],
                   geometry = sf::st_make_valid(geom))
  out <- out[order(out$nome, out$codigo), ]
  # Mesmo nome em distritos diferentes (raro): desambigua pelo código.
  dup <- out$nome %in% out$nome[duplicated(out$nome)]
  out$nome[dup] <- paste0(out$nome[dup], " (", out$codigo[dup], ")")
  attr(out, "rotulos") <- rotulos
  out
}

# Índice (base 0) da subdivisão em que cada local cai; -1 sem coordenada ou
# fora de toda subdivisão (área rural, ilha).
atribuir_subdivisao <- function(locais, subdiv) {
  idx <- rep(-1L, nrow(locais))
  if (is.null(subdiv)) return(idx)
  tem <- which(!is.na(locais$lat))
  pts <- sf::st_as_sf(locais[tem], coords = c("lon", "lat"), crs = 4326)
  pts <- sf::st_transform(pts, sf::st_crs(subdiv))
  sf::sf_use_s2(FALSE)
  on.exit(sf::sf_use_s2(TRUE), add = TRUE)
  dentro <- suppressMessages(sf::st_within(pts, subdiv))
  idx[tem] <- vapply(dentro, function(x) if (length(x) > 0) as.integer(x[[1]]) - 1L else -1L, integer(1))
  idx
}

exportar_topojson_subdivisoes <- function(subdiv, caminho) {
  dir.create(dirname(caminho), showWarnings = FALSE, recursive = TRUE)
  s <- sf::st_sf(i = seq_len(nrow(subdiv)) - 1L, nome = subdiv$nome, geometry = sf::st_geometry(subdiv))
  simpl <- rmapshaper::ms_simplify(s, keep = KEEP_SUBDIVISAO, keep_shapes = TRUE)
  geojsonio::topojson_write(simpl, file = caminho, object_name = "subdivisoes",
                            quantization = QUANTIZACAO, overwrite = TRUE)
  invisible(caminho)
}

# --- montagem do arquivo da capital -------------------------------------------------

# v: votos classificados (classificar_votos_secao); locais: montar_locais na
# ordem final; exib: sq dos candidatos exibidos da UF.
montar_votos_capital <- function(v, locais, exib) {
  chaves <- paste(locais$nr_zona, locais$nr_local)
  v[, i := match(paste(nr_zona, nr_local), chaves)]
  if (anyNA(v$i)) stop("Voto em local fora da lista de locais")
  n <- nrow(locais)
  idx <- seq_len(n)
  vetor <- function(i, x) denso(i, x, idx)
  fed <- v[cargo == "federal"]
  out <- list(
    comparecimento = vetor(fed[, sum(votos), by = i]$i, fed[, sum(votos), by = i]$V1),
    cargos = list()
  )
  for (cg in CARGOS_EXPORT) {
    d <- v[cargo == cg]
    tot <- function(tipos) {
      s <- d[tipo %in% tipos, .(t = sum(votos)), by = i]
      vetor(s$i, s$t)
    }
    p <- d[tipo %in% c("nominal", "legenda"), .(votos = sum(votos)), by = .(sigla, i)]
    siglas <- p[, .(t = sum(votos)), by = sigla][t > 0][order(-t)]$sigla
    cv <- d[tipo == "nominal" & sq_candidato %in% exib, .(votos = sum(votos)), by = .(sq_candidato, i)][votos > 0]
    sqs <- cv[, .(t = sum(votos)), by = sq_candidato][order(-t)]$sq_candidato
    out$cargos[[cg]] <- list(
      validos = tot(c("nominal", "legenda")),
      brancos = tot("branco"),
      nulos = tot("nulo"),
      partidos = stats::setNames(lapply(siglas, function(s) {
        q <- p[sigla == s]
        vetor(q$i, q$votos)
      }), siglas),
      candidatos = stats::setNames(lapply(sqs, function(s) {
        q <- cv[sq_candidato == s]
        esparso(q$i, q$votos, idx)
      }), sqs)
    )
  }
  out
}

# Confere os totais da capital (soma dos locais) contra o munzona, já
# exportado em output/votos/{UF}.json: válidos, brancos, nulos e cada
# partido, por cargo. Devolve as diferenças (data.table vazio = bate).
conferir_capital <- function(cap, uf) {
  ref <- jsonlite::fromJSON(file.path(DIR_OUTPUT, "votos", paste0(uf, ".json")), simplifyVector = TRUE)
  j <- match(CAPITAIS[[uf]], ref$municipios)
  dif <- list()
  anotar <- function(cargo, item, capital, munzona) {
    if (capital != munzona) dif[[length(dif) + 1]] <<- data.frame(uf, cargo, item, capital, munzona)
  }
  anotar("federal", "comparecimento", sum(cap$comparecimento), ref$comparecimento[j])
  for (cg in names(cap$cargos)) {
    a <- cap$cargos[[cg]]
    b <- ref$cargos[[cg]]
    for (k in c("validos", "brancos", "nulos")) anotar(cg, k, sum(a[[k]]), b[[k]][j])
    for (s in union(names(a$partidos), names(b$partidos))) {
      anotar(cg, s, if (is.null(a$partidos[[s]])) 0 else sum(a$partidos[[s]]),
             if (is.null(b$partidos[[s]])) 0 else b$partidos[[s]][j])
    }
  }
  data.table::rbindlist(dif)
}

# Vizinhança queen das subdivisões (base 0), para o LISA.
vizinhos_subdivisoes <- function(subdiv) {
  if (is.null(subdiv) || nrow(subdiv) < 2) return(list())
  sf::sf_use_s2(FALSE)
  on.exit(sf::sf_use_s2(TRUE), add = TRUE)
  nb <- suppressWarnings(spdep::poly2nb(subdiv, queen = TRUE))
  lapply(nb, function(v) I(as.integer(v[v > 0] - 1L)))
}
