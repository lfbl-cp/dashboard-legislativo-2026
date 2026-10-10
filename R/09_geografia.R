# =============================================================================
# Geografia: malha municipal do IBGE (geobr), de-para TSE -> IBGE e
# município -> micro/mesorregião, e exportação em TopoJSON.
#
# Só a malha MUNICIPAL é exportada. Micro, meso e contorno de UF são fundidos
# no navegador (topojson.merge) a partir dos municípios, usando code_micro /
# code_meso nas propriedades -- economiza um arquivo por nível.
#
#   output/geo/municipios_BR.topojson   visão "Brasil" (simplificação forte)
#   output/geo/municipios_{UF}.topojson visão de uma UF (mais detalhe)
# =============================================================================

# 2025: a malha de 2022 não tem Boa Esperança do Norte (MT, instalado em
# 2025), que já vota em 2026 -- 5.571 municípios.
ANO_MALHA <- 2025
ANO_MALHA_REGIOES <- 2020 # meso/micro (o geobr não tem 2022 para esses níveis)
KEEP_NACIONAL <- 0.05     # fração de vértices mantida (validado no clone: ~6 MB)
KEEP_UF <- 0.15           # idem, por UF (padrão do clone)
QUANTIZACAO <- 1e5

# Cache dos downloads do geobr em data/raw/ (o geobr baixa a cada sessão).
ler_geobr_cache <- function(nome, ler) {
  arq <- file.path(DIR_RAW, sprintf("geobr_%s.rds", nome))
  if (file.exists(arq)) return(readRDS(arq))
  x <- ler()
  saveRDS(x, arq)
  x
}

# De-para código TSE -> IBGE (7 dígitos), via linkador_bases.xlsx (fornecido
# pelo usuário, 5.570 municípios) + linkador_complemento.csv (municípios
# criados depois, ex. Boa Esperança do Norte/MT, 2025).
ler_crosswalk_tse_ibge <- function() {
  l <- readxl::read_excel(file.path(DIR_REF, "linkador_bases.xlsx"), sheet = "Sheet1")
  comp <- utils::read.csv(file.path(DIR_REF, "linkador_complemento.csv"), encoding = "UTF-8",
                          stringsAsFactors = FALSE)
  out <- data.frame(uf = c(l$estado_abrev, comp$estado_abrev),
                    cd_municipio_tse = as.integer(c(l$id_TSE, comp$id_TSE)),
                    code_muni = as.integer(c(l$id_munic_7, comp$id_munic_7)),
                    nome = c(l$municipio, comp$municipio), stringsAsFactors = FALSE)
  stopifnot("Município duplicado no crosswalk" = !anyDuplicated(out$code_muni),
            "Código TSE duplicado no crosswalk" = !anyDuplicated(paste(out$uf, out$cd_municipio_tse)))
  out
}

# sf dos 5.570 municípios com code_micro/code_meso (+ nomes) derivados por
# join espacial: centroide (ponto interior, para não cair fora em municípios
# côncavos) dentro do polígono de micro/meso. Micro e meso nunca cruzam
# fronteira de UF, então a correspondência é 1:1.
montar_municipios_sf <- function() {
  mun <- ler_geobr_cache(sprintf("municipios_%d", ANO_MALHA), function() {
    geobr::read_municipality(code_muni = "all", year = ANO_MALHA, showProgress = FALSE)
  })
  meso <- ler_geobr_cache(sprintf("meso_%d", ANO_MALHA_REGIOES), function() {
    geobr::read_meso_region(code_meso = "all", year = ANO_MALHA_REGIOES, showProgress = FALSE)
  })
  micro <- ler_geobr_cache(sprintf("micro_%d", ANO_MALHA_REGIOES), function() {
    geobr::read_micro_region(code_micro = "all", year = ANO_MALHA_REGIOES, showProgress = FALSE)
  })
  meso <- sf::st_transform(meso, sf::st_crs(mun))
  micro <- sf::st_transform(micro, sf::st_crs(mun))

  sf::sf_use_s2(FALSE)
  on.exit(sf::sf_use_s2(TRUE), add = TRUE)
  pontos <- suppressWarnings(sf::st_point_on_surface(sf::st_geometry(mun)))
  primeiro <- function(idx) vapply(idx, function(x) if (length(x) > 0) x[[1]] else NA_integer_, integer(1))
  i_meso <- primeiro(sf::st_within(pontos, sf::st_geometry(meso)))
  i_micro <- primeiro(sf::st_within(pontos, sf::st_geometry(micro)))
  # Ponto que cai num vão entre polígonos (malhas de anos diferentes): usa o
  # polígono mais próximo.
  for (nome in c("i_meso", "i_micro")) {
    idx <- get(nome)
    alvo <- if (nome == "i_meso") meso else micro
    falta <- which(is.na(idx))
    if (length(falta) > 0) idx[falta] <- sf::st_nearest_feature(pontos[falta], alvo)
    assign(nome, idx)
  }

  # Nome do linkador: o geobr grafa "Abreu E Lima", "Olho D'água".
  cw <- ler_crosswalk_tse_ibge()
  nomes <- cw$nome[match(as.integer(mun$code_muni), cw$code_muni)]
  out <- sf::st_sf(
    code_muni = as.integer(mun$code_muni),
    name_muni = ifelse(is.na(nomes), mun$name_muni, nomes),
    uf = mun$abbrev_state,
    code_micro = as.integer(micro$code_micro[i_micro]),
    name_micro = micro$name_micro[i_micro],
    code_meso = as.integer(meso$code_meso[i_meso]),
    name_meso = meso$name_meso[i_meso],
    geometry = sf::st_geometry(mun)
  )
  # Sanidade: micro/meso de cada município na mesma UF (2 primeiros
  # dígitos do código IBGE).
  uf_mun <- substr(out$code_muni, 1, 2)
  ruins <- which(substr(out$code_micro, 1, 2) != uf_mun | substr(out$code_meso, 1, 2) != uf_mun)
  if (length(ruins) > 0) {
    stop("Micro/meso em UF diferente do município: ", paste(out$name_muni[ruins], collapse = ", "))
  }
  out
}

# Simplifica (preservando a topologia entre vizinhos) e grava TopoJSON só com
# as propriedades que o front-end usa.
exportar_topojson <- function(sf_obj, caminho, keep) {
  dir.create(dirname(caminho), showWarnings = FALSE, recursive = TRUE)
  props <- sf_obj[, c("code_muni", "name_muni", "uf", "code_micro", "code_meso")]
  simpl <- rmapshaper::ms_simplify(props, keep = keep, keep_shapes = TRUE)
  geojsonio::topojson_write(simpl, file = caminho, object_name = "municipios",
                            quantization = QUANTIZACAO, overwrite = TRUE)
  invisible(caminho)
}
