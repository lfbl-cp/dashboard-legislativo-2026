# =============================================================================
# Orquestração do pipeline.
#
#   Rscript pipeline/run_pipeline.R                    # todas as etapas
#   Rscript pipeline/run_pipeline.R --etapa=candidatos # só uma (ou várias,
#                                                      # separadas por vírgula)
#
# Etapas (em ordem):
#   candidatos  consulta_cand 2026 (27 UFs) + senadores 2022 -> candidatos,
#               partidos, federações e cadeiras de cada Casa, validados
#   votos       votos por candidato x município (munzona, UF a UF); define
#               os exibidos (eleitos + 3 primeiros suplentes por lista;
#               senadores todos) e busca as redes sociais deles
#   fotos       fotos oficiais dos exibidos -> output/fotos/ (apaga as de
#               quem deixou de ser exibido)
#   composicao  cadeiras de todas as Casas -> output/composicao.json
#   geografia   malha municipal (IBGE/geobr) + micro/meso -> output/geo/
#   exportar    meta.json, votos/{UF}.json, votos/BR.json, candidatos/{UF}.json
#               (somas validadas contra o detalhe oficial do TSE)
# =============================================================================

suppressPackageStartupMessages({
  library(data.table)
})

# Raiz do projeto = pasta acima de pipeline/, de onde quer que se rode.
local({
  arq <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  raiz <- if (length(arq) == 1) normalizePath(file.path(dirname(arq), "..")) else getwd()
  setwd(raiz)
})
for (f in sort(list.files("R", pattern = "\\.R$", full.names = TRUE))) source(f, encoding = "UTF-8")

ETAPAS <- c("candidatos", "votos", "fotos", "composicao", "geografia", "exportar")

args <- commandArgs(trailingOnly = TRUE)
etapas <- ETAPAS
arg_etapa <- grep("^--etapa=", args, value = TRUE)
if (length(arg_etapa) == 1) {
  etapas <- strsplit(sub("^--etapa=", "", arg_etapa), ",")[[1]]
  desconhecidas <- setdiff(etapas, ETAPAS)
  if (length(desconhecidas) > 0) stop("Etapa desconhecida: ", paste(desconhecidas, collapse = ", "))
}
dir.create(DIR_PROCESSED, showWarnings = FALSE, recursive = TRUE)

# --- candidatos ------------------------------------------------------------------
etapa_candidatos <- function() {
  candidatos <- montar_candidatos(ler_candidatos(ANO))
  senado_anterior <- montar_candidatos(ler_candidatos(ANO_SENADO_ANTERIOR))
  senado_anterior <- senado_anterior[senado_anterior$cargo == "senador" &
                                       senado_anterior$situacao %in% "eleito", ]
  senado_anterior$exibir <- TRUE

  partidos_ref <- ler_partidos_ref()
  validar_partidos(c(candidatos$sigla, senado_anterior$sigla), partidos_ref)
  federacoes <- montar_federacoes(candidatos, partidos_ref)
  partidos <- montar_partidos(partidos_ref, federacoes)

  cadeiras <- montar_cadeiras(candidatos, senado_anterior)
  validar_cadeiras(cadeiras)

  sem_posicao <- unique(cadeiras$sigla[is.na(partidos$ideologia[match(cadeiras$sigla, partidos$sigla)])])
  if (length(sem_posicao) > 0) {
    message("Aviso: partido(s) com cadeira e sem posição ideológica (partidos.csv): ",
            paste(sem_posicao, collapse = ", "))
  }

  todos <- rbind(candidatos, senado_anterior)
  saveRDS(todos, file.path(DIR_PROCESSED, "candidatos.rds"))
  saveRDS(partidos, file.path(DIR_PROCESSED, "partidos.rds"))
  saveRDS(federacoes, file.path(DIR_PROCESSED, "federacoes.rds"))
  saveRDS(cadeiras, file.path(DIR_PROCESSED, "cadeiras.rds"))

  cat(sprintf("\nCandidatos 2026: %d | senadores 2022: %d\n", nrow(candidatos), nrow(senado_anterior)))
  print(table(candidatos$cargo, candidatos$situacao, useNA = "ifany"))
  cat("\nCadeiras por Casa:\n")
  n <- table(cadeiras$casa)
  print(n[c("camara", "senado")])
  cat(sprintf("Assembleias: %d cadeiras em %d Casas\n",
              sum(n[grepl("^assembleia_", names(n))]), sum(grepl("^assembleia_", names(n)))))
  cat("\nCâmara por partido:\n")
  print(sort(table(cadeiras$sigla[cadeiras$casa == "camara"]), decreasing = TRUE))
  cat("\nSenado por partido (renovadas em 2026 / eleitos em 2022):\n")
  print(table(cadeiras$sigla[cadeiras$casa == "senado"], cadeiras$ano[cadeiras$casa == "senado"]))
}

# --- votos -------------------------------------------------------------------------
etapa_votos <- function() {
  candidatos <- readRDS(file.path(DIR_PROCESSED, "candidatos.rds"))
  votos <- obter_votos_candidato(ANO)
  saveRDS(votos, file.path(DIR_PROCESSED, "votos_candidato_municipio.rds"))

  eleitos <- candidatos$sq_candidato[candidatos$situacao %in% "eleito" & candidatos$ano == ANO]
  sem_voto <- setdiff(eleitos, votos$sq_candidato)
  if (length(sem_voto) > 0) stop("Eleito(s) sem nenhuma linha no munzona: ", paste(sem_voto, collapse = ", "))

  candidatos <- definir_exibidos(candidatos, votos)
  redes <- montar_redes(ANO, candidatos$sq_candidato[candidatos$exibir])
  candidatos$redes <- unname(redes[candidatos$sq_candidato])
  saveRDS(candidatos, file.path(DIR_PROCESSED, "candidatos.rds"))

  cat(sprintf("Linhas candidato x município: %d | candidatos com voto: %d\n",
              nrow(votos), data.table::uniqueN(votos$sq_candidato)))
  ex <- candidatos[candidatos$exibir, ]
  cat(sprintf("Exibidos: %d (deputados eleitos %d, suplentes %d, senadores %d)\n", nrow(ex),
              sum(ex$situacao %in% "eleito" & ex$cargo != "senador"),
              sum(ex$situacao %in% "suplente"), sum(ex$cargo == "senador")))
}

# --- fotos -------------------------------------------------------------------------
etapa_fotos <- function() {
  candidatos <- readRDS(file.path(DIR_PROCESSED, "candidatos.rds"))
  if (is.null(candidatos$ordem_suplente)) stop("Rode a etapa votos antes das fotos.")
  removidas <- remover_fotos_nao_exibidas(candidatos)
  if (removidas > 0) cat(sprintf("Fotos removidas (deixaram de ser exibidas): %d\n", removidas))
  extrair_fotos(candidatos)
  cat("Senadores de", ANO_SENADO_ANTERIOR, "(TSE x API do Senado, casados por UF):\n")
  print(extrair_fotos_senado_anterior(candidatos), row.names = FALSE)
  candidatos$tem_foto <- file.exists(file.path(DIR_FOTOS, paste0(candidatos$sq_candidato, ".jpg")))
  saveRDS(candidatos, file.path(DIR_PROCESSED, "candidatos.rds"))
  ex <- candidatos[candidatos$exibir, ]
  cat(sprintf("Exibidos: %d | com foto: %d | sem foto: %d\n",
              nrow(ex), sum(ex$tem_foto), sum(!ex$tem_foto)))
  if (any(!ex$tem_foto)) print(ex[!ex$tem_foto, c("uf", "cargo", "nome", "ds_situacao_tse")], row.names = FALSE)
  tam <- sum(file.size(list.files(DIR_FOTOS, full.names = TRUE)))
  cat(sprintf("output/fotos/: %.1f MB\n", tam / 1024^2))
}

# --- composicao -------------------------------------------------------------------
etapa_composicao <- function() {
  ler <- function(nome) readRDS(file.path(DIR_PROCESSED, paste0(nome, ".rds")))
  candidatos <- ler("candidatos")
  if (is.null(candidatos$tem_foto)) stop("Rode a etapa fotos antes da composicao.")
  comp <- montar_composicao(ler("cadeiras"), candidatos)
  arq <- exportar_json(comp, file.path(DIR_OUTPUT, "composicao.json"))
  cat(sprintf("%s: %d Casas, %d cadeiras, %.0f KB\n", arq, length(comp$casas),
              sum(vapply(comp$casas, `[[`, integer(1), "total")), file.size(arq) / 1024))
}

# --- geografia ---------------------------------------------------------------------
etapa_geografia <- function() {
  mun <- montar_municipios_sf()
  saveRDS(sf::st_drop_geometry(mun), file.path(DIR_PROCESSED, "municipios.rds"))
  exportar_topojson(mun, file.path(DIR_OUTPUT, "geo", "municipios_BR.topojson"), KEEP_NACIONAL)
  for (uf in UFS_BRASIL) {
    exportar_topojson(mun[mun$uf == uf, ], file.path(DIR_OUTPUT, "geo", sprintf("municipios_%s.topojson", uf)), KEEP_UF)
  }
  tam <- file.size(list.files(file.path(DIR_OUTPUT, "geo"), full.names = TRUE))
  cat(sprintf("%d municípios, %d micro, %d meso | output/geo/: %d arquivos, %.1f MB\n",
              nrow(mun), length(unique(mun$code_micro)), length(unique(mun$code_meso)),
              length(tam), sum(tam) / 1024^2))
}

# --- exportar ----------------------------------------------------------------------
etapa_exportar <- function() {
  ler <- function(nome) readRDS(file.path(DIR_PROCESSED, paste0(nome, ".rds")))
  candidatos <- ler("candidatos")
  municipios <- ler("municipios")
  cw <- ler_crosswalk_tse_ibge()

  detalhe <- com_ibge(ler_detalhe(ANO), cw)
  partidos_v <- com_ibge(ler_votos_partido(ANO), cw)
  votos_c <- com_ibge(ler("votos_candidato_municipio"), cw)

  # Coerência entre os arquivos do TSE: votos nominais por partido x
  # município (arquivo por partido) = soma dos candidatos (arquivo por
  # candidato).
  sigla_cand <- data.table::data.table(sq_candidato = candidatos$sq_candidato, sigla = candidatos$sigla)
  nom_c <- merge(votos_c, sigla_cand, by = "sq_candidato")[, .(nc = sum(votos)), by = .(code_muni, cargo, sigla)]
  conf <- merge(partidos_v[, .(code_muni, cargo, sigla, nominal)], nom_c, by = c("code_muni", "cargo", "sigla"), all = TRUE)
  conf[is.na(nominal), nominal := 0L][is.na(nc), nc := 0L]
  if (any(conf$nominal != conf$nc)) {
    stop(sprintf("Nominal por partido != soma dos candidatos em %d linha(s)", sum(conf$nominal != conf$nc)))
  }

  exib <- candidatos$sq_candidato[candidatos$exibir & candidatos$ano == ANO]
  dir.create(file.path(DIR_OUTPUT, "votos"), showWarnings = FALSE, recursive = TRUE)
  dir.create(file.path(DIR_OUTPUT, "candidatos"), showWarnings = FALSE, recursive = TRUE)
  for (uf_i in UFS_BRASIL) {
    mun_uf <- sort(municipios$code_muni[municipios$uf == uf_i])
    v <- montar_votos_escopo(mun_uf, detalhe[uf == uf_i], partidos_v[uf == uf_i],
                             votos_c[uf == uf_i & sq_candidato %in% exib])
    validar_votos_escopo(v, uf_i)
    exportar_json(c(list(uf = uf_i), v), file.path(DIR_OUTPUT, "votos", paste0(uf_i, ".json")))
    cand_uf <- candidatos[candidatos$exibir & candidatos$uf == uf_i, ]
    exportar_json(montar_candidatos_uf(cand_uf), file.path(DIR_OUTPUT, "candidatos", paste0(uf_i, ".json")))
  }
  br <- montar_votos_escopo(sort(municipios$code_muni), detalhe, partidos_v)
  validar_votos_escopo(br, "BR")
  exportar_json(c(list(uf = "BR"), br), file.path(DIR_OUTPUT, "votos", "BR.json"))
  exportar_json(montar_meta(ler("partidos"), ler("federacoes")), file.path(DIR_OUTPUT, "meta.json"))

  tam <- function(p) sum(file.size(list.files(file.path(DIR_OUTPUT, p), full.names = TRUE))) / 1024^2
  cat(sprintf("Somas conferidas contra o detalhe do TSE em %d UFs + BR (partidos = válidos; nominal = soma dos candidatos).\n",
              length(UFS_BRASIL)))
  cat(sprintf("output/votos/: %.1f MB (BR.json %.1f MB) | output/candidatos/: %.1f MB\n",
              tam("votos"), file.size(file.path(DIR_OUTPUT, "votos", "BR.json")) / 1024^2, tam("candidatos")))
}

for (e in etapas) {
  cat(sprintf("\n==================== %s ====================\n", e))
  t0 <- Sys.time()
  get(paste0("etapa_", e))()
  cat(sprintf("-- %s ok em %.0fs\n", e, as.numeric(difftime(Sys.time(), t0, units = "secs"))))
}
