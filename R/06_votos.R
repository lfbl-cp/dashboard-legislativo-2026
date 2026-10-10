# =============================================================================
# Votos por candidato e município (votacao_candidato_munzona, um CSV por UF
# dentro do ZIP nacional; 3,2 GB descompactados no total). Processa UF a UF:
# extrai o CSV para um temporário, lê só as colunas usadas, soma as zonas e
# apaga o CSV -- o bruto descompactado nunca fica em disco.
#
# Também decide quem é exibido no painel por candidato: deputados eleitos +
# os N_SUPLENTES primeiros suplentes de cada lista (ordem por votos
# nominais); senadores, todos.
# =============================================================================

N_SUPLENTES <- 3

COLUNAS_VOTOS <- c("NR_TURNO", "SG_UF", "CD_MUNICIPIO", "CD_CARGO", "SQ_CANDIDATO",
                   "QT_VOTOS_NOMINAIS_VALIDOS")

# Votos nominais válidos por candidato x município de uma UF (zonas somadas),
# só cargos do painel e 1º turno.
agregar_votos_uf <- function(zip, ano, uf) {
  csv <- sprintf("votacao_candidato_munzona_%d_%s.csv", ano, uf)
  tmp <- tempfile("munzona_")
  dir.create(tmp)
  on.exit(unlink(tmp, recursive = TRUE), add = TRUE)
  utils::unzip(zip, files = csv, exdir = tmp)
  x <- ler_csv_tse(file.path(tmp, csv), select = COLUNAS_VOTOS)
  x <- x[NR_TURNO == TURNO & CD_CARGO %in% CARGOS$cd_cargo]
  x[, .(votos = sum(QT_VOTOS_NOMINAIS_VALIDOS, na.rm = TRUE)),
    by = .(uf = SG_UF, cd_municipio_tse = CD_MUNICIPIO, cd_cargo = CD_CARGO,
           sq_candidato = as.character(SQ_CANDIDATO))]
}

# Todas as UFs; cache por UF em data/processed/votos_uf/ (reprocessar uma UF
# = apagar o rds dela).
obter_votos_candidato <- function(ano = ANO) {
  zip <- obter_zip_tse(url_munzona(ano))
  pasta <- file.path(DIR_PROCESSED, "votos_uf")
  dir.create(pasta, showWarnings = FALSE, recursive = TRUE)
  partes <- lapply(UFS_BRASIL, function(uf) {
    cache <- file.path(pasta, sprintf("%d_%s.rds", ano, uf))
    if (file.exists(cache)) return(readRDS(cache))
    message(sprintf("  votos %s ...", uf))
    v <- agregar_votos_uf(zip, ano, uf)
    saveRDS(v, cache)
    v
  })
  data.table::rbindlist(partes)
}

# Acrescenta votos_total, lista, ordem_suplente e redefine `exibir`.
# lista = federação (se houver) ou partido, por UF e cargo -- é a unidade
# que disputa as cadeiras e dentro da qual se ordena a suplência.
definir_exibidos <- function(candidatos, votos, n_suplentes = N_SUPLENTES) {
  tot <- votos[, .(votos_total = sum(votos)), by = sq_candidato]
  candidatos$votos_total <- tot$votos_total[match(candidatos$sq_candidato, tot$sq_candidato)]
  # Sem linha no munzona = 0 voto; senadores de 2022 não têm votos nesta
  # eleição e ficam NA.
  candidatos$votos_total[is.na(candidatos$votos_total) & candidatos$ano == ANO] <- 0L
  candidatos$lista <- ifelse(is.na(candidatos$nr_federacao), candidatos$sigla,
                             paste0("F", candidatos$nr_federacao))

  candidatos$ordem_suplente <- NA_integer_
  sup <- which(candidatos$situacao %in% "suplente" & candidatos$tipo == "proporcional")
  chave <- paste(candidatos$uf[sup], candidatos$cargo[sup], candidatos$lista[sup])
  ord <- order(chave, -candidatos$votos_total[sup], candidatos$nome[sup])
  sup <- sup[ord]
  candidatos$ordem_suplente[sup] <- stats::ave(seq_along(sup), chave[ord], FUN = seq_along)

  candidatos$exibir <- candidatos$cargo == "senador" |
    candidatos$situacao %in% "eleito" |
    (!is.na(candidatos$ordem_suplente) & candidatos$ordem_suplente <= n_suplentes)
  candidatos
}
