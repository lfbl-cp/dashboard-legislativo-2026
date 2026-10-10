# =============================================================================
# Partidos e federações: cor e posição ideológica vêm de tabelas versionadas
# em data-raw/ref/ (ver README lá); a composição das federações vem do TSE.
# =============================================================================

ler_partidos_ref <- function() {
  x <- utils::read.csv(file.path(DIR_REF, "partidos.csv"), encoding = "UTF-8",
                       colClasses = c(nr_2026 = "integer", ideologia = "numeric"),
                       stringsAsFactors = FALSE)
  stopifnot("Sigla duplicada em partidos.csv" = !anyDuplicated(x$sigla))
  x
}

ler_federacoes_ref <- function() {
  utils::read.csv(file.path(DIR_REF, "federacoes.csv"), encoding = "UTF-8",
                  colClasses = c(nr = "integer"), stringsAsFactors = FALSE)
}

# Para se algum partido dos dados não estiver catalogado (sem cor/ideologia).
validar_partidos <- function(siglas, partidos_ref) {
  faltam <- setdiff(unique(siglas), partidos_ref$sigla)
  if (length(faltam) > 0) {
    stop("Partido(s) sem linha em data-raw/ref/partidos.csv: ", paste(faltam, collapse = ", "))
  }
  invisible(TRUE)
}

# Federações de 2026 a partir dos candidatos (NR_FEDERACAO por partido) +
# nome/cor da tabela de referência. Posição ideológica da federação = média
# simples das posições dos partidos membros (o survey não classifica
# federações).
montar_federacoes <- function(candidatos, partidos_ref) {
  pf <- unique(candidatos[!is.na(candidatos$nr_federacao), c("sigla", "nr_federacao")])
  stopifnot("Partido em mais de uma federação" = !anyDuplicated(pf$sigla))
  ref <- ler_federacoes_ref()
  faltam <- setdiff(pf$nr_federacao, ref$nr)
  if (length(faltam) > 0) {
    stop("Federação sem linha em data-raw/ref/federacoes.csv: ", paste(faltam, collapse = ", "))
  }
  ref <- ref[ref$nr %in% pf$nr_federacao, ]
  ref$partidos <- lapply(ref$nr, function(f) pf$sigla[pf$nr_federacao == f])
  ref$ideologia <- vapply(ref$partidos, function(p) {
    mean(partidos_ref$ideologia[match(p, partidos_ref$sigla)], na.rm = TRUE)
  }, numeric(1))
  stopifnot("Federação com menos de 2 partidos" = all(lengths(ref$partidos) >= 2))
  ref
}

# Tabela de partidos do painel: referência + federação de 2026 de cada um.
montar_partidos <- function(partidos_ref, federacoes) {
  p <- partidos_ref
  p$nr_federacao <- NA_integer_
  for (i in seq_len(nrow(federacoes))) {
    p$nr_federacao[p$sigla %in% federacoes$partidos[[i]]] <- federacoes$nr[i]
  }
  p
}
