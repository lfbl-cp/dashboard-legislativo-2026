# =============================================================================
# Composição das Casas -> output/composicao.json, que alimenta a aba
# Composição (hemiciclos). Um arquivo só (todas as Casas, ~1.650 cadeiras),
# com o essencial de cada cadeira; partidos/federações vêm de meta.json e os
# dados de card de candidatos/{UF}.json (carregado no clique).
#
# A ordem das cadeiras no hemiciclo (esquerda -> direita) é decidida no
# front-end, a partir de `ideologia` de partidos/federações, porque depende do
# agrupamento escolhido (partido ou federação).
# =============================================================================

montar_composicao <- function(cadeiras, candidatos) {
  cand <- candidatos[match(cadeiras$sq_candidato, candidatos$sq_candidato), ]
  stopifnot("Cadeira sem candidato correspondente" = !anyNA(cand$sq_candidato))

  casas_ids <- c("camara", "senado", paste0("assembleia_", UFS_BRASIL))
  casas <- lapply(casas_ids, function(id) {
    idx <- which(cadeiras$casa == id)
    uf <- if (startsWith(id, "assembleia_")) sub("^assembleia_", "", id) else NA_character_
    list(
      nome = if (is.na(uf)) CASAS[[id]] else nome_assembleia(uf),
      uf = uf,
      total = length(idx),
      cadeiras = lapply(idx, function(i) {
        list(sq = cand$sq_candidato[i], nome = cand$nome[i], sigla = cand$sigla[i],
             uf = cand$uf[i], ano = cand$ano[i], foto = isTRUE(cand$tem_foto[i]))
      })
    )
  })
  names(casas) <- casas_ids
  list(casas = casas)
}

exportar_json <- function(x, caminho) {
  dir.create(dirname(caminho), showWarnings = FALSE, recursive = TRUE)
  jsonlite::write_json(x, caminho, auto_unbox = TRUE, null = "null", na = "null", digits = NA)
  invisible(caminho)
}
