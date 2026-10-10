# =============================================================================
# Composição das Casas -> output/composicao.json, que alimenta a aba
# Composição (hemiciclos). Um arquivo só (todas as Casas): ~1.650 cadeiras,
# pequeno o bastante para não valer dividir por Casa.
#
# A ordem das cadeiras no hemiciclo (esquerda -> direita) é decidida no
# front-end, a partir de `ideologia` de partidos/federações, porque depende do
# agrupamento escolhido (partido ou federação).
# =============================================================================

COLUNAS_CARD <- c("nome", "nome_completo", "sigla", "uf", "ano", "ds_situacao_tse",
                  "coligacao", "idade", "genero", "ocupacao", "instrucao", "tem_foto")

montar_composicao <- function(cadeiras, candidatos, partidos, federacoes) {
  cand <- candidatos[match(cadeiras$sq_candidato, candidatos$sq_candidato), ]
  stopifnot("Cadeira sem candidato correspondente" = !anyNA(cand$sq_candidato))
  # Situação curta para o card: "QP"/"média" nos proporcionais; senador é
  # "ELEITO" sem qualificação.
  sit <- ifelse(grepl("QP", cand$ds_situacao_tse), "QP",
                ifelse(grepl("M.DIA", cand$ds_situacao_tse), "média", NA_character_))

  cadeira_json <- function(i) {
    c(list(sq = cand$sq_candidato[i], nome = cand$nome[i], nome_completo = cand$nome_completo[i],
           sigla = cand$sigla[i], uf = cand$uf[i], ano = cand$ano[i], sit = sit[i],
           coligacao = cand$coligacao[i], idade = cand$idade[i], genero = cand$genero[i],
           ocupacao = cand$ocupacao[i], instrucao = cand$instrucao[i],
           foto = isTRUE(cand$tem_foto[i])),
      if (length(cand$redes[[i]]) > 0) list(redes = I(cand$redes[[i]])))
  }

  casas_ids <- c("camara", "senado", paste0("assembleia_", UFS_BRASIL))
  casas <- lapply(casas_ids, function(id) {
    idx <- which(cadeiras$casa == id)
    uf <- if (startsWith(id, "assembleia_")) sub("^assembleia_", "", id) else NA_character_
    list(
      nome = if (is.na(uf)) CASAS[[id]] else nome_assembleia(uf),
      uf = uf,
      total = length(idx),
      cadeiras = lapply(idx, cadeira_json)
    )
  })
  names(casas) <- casas_ids

  usados <- sort(unique(cadeiras$sigla))
  p <- partidos[partidos$sigla %in% usados, ]
  partidos_json <- lapply(seq_len(nrow(p)), function(i) {
    list(rotulo = p$rotulo[i], cor = p$cor[i], ideologia = p$ideologia[i],
         federacao = if (is.na(p$nr_federacao[i])) NULL else as.character(p$nr_federacao[i]))
  })
  names(partidos_json) <- p$sigla

  federacoes_json <- lapply(seq_len(nrow(federacoes)), function(i) {
    list(sigla = federacoes$sigla[i], nome = federacoes$nome[i], cor = federacoes$cor[i],
         ideologia = round(federacoes$ideologia[i], 3), partidos = I(federacoes$partidos[[i]]))
  })
  names(federacoes_json) <- as.character(federacoes$nr)

  list(
    ano = ANO,
    ano_senado_anterior = ANO_SENADO_ANTERIOR,
    gerado_em = format(Sys.Date()),
    fonte_ideologia = paste("Bolognesi, Ribeiro, Codato & Silva (2025), Opinião Pública 31,",
                            "e31120 — média dos experts em 2022 (0 = esquerda, 10 = direita)"),
    partidos = partidos_json,
    federacoes = federacoes_json,
    casas = casas
  )
}

exportar_json <- function(x, caminho) {
  dir.create(dirname(caminho), showWarnings = FALSE, recursive = TRUE)
  jsonlite::write_json(x, caminho, auto_unbox = TRUE, null = "null", na = "null", digits = NA)
  invisible(caminho)
}
