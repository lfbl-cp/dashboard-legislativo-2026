arq_votos <- function(uf) file.path(DIR_OUTPUT, "votos", paste0(uf, ".json"))
ler_json <- function(p) jsonlite::fromJSON(p, simplifyVector = TRUE)

test_that("pares esparsos e vetores densos seguem a ordem dos municípios", {
  mun <- c(10L, 20L, 30L)
  # unclass(): tira o I() que força lista no JSON (ver denso()).
  expect_equal(unclass(denso(c(30L, 10L), c(5, 7), mun)), c(7L, 0L, 5L))
  expect_equal(unclass(esparso(c(30L, 10L), c(5, 7), mun)), c(0L, 7L, 2L, 5L))
  expect_equal(jsonlite::toJSON(list(a = denso(10L, 3, 10L)), auto_unbox = TRUE), jsonlite::toJSON(list(a = list(3L)), auto_unbox = TRUE))
})

test_that("votos por UF cobrem os 5.571 municípios e fecham com os válidos", {
  skip_if_not(file.exists(arq_votos("PE")), "rode o pipeline (etapa exportar) antes")
  total_mun <- 0
  for (uf in UFS_BRASIL) {
    v <- ler_json(arq_votos(uf))
    total_mun <- total_mun + length(v$municipios)
    for (cg in c("federal", "estadual", "senador")) {
      c <- v$cargos[[cg]]
      expect_equal(Reduce(`+`, c$partidos), c$validos, info = paste(uf, cg))
      # candidatos: pares [índice, votos] com índice dentro da UF
      idx <- unlist(lapply(c$candidatos, function(p) p[c(TRUE, FALSE)]))
      expect_true(all(idx >= 0 & idx < length(v$municipios)), info = paste(uf, cg))
    }
    # senador: todos os candidatos estão no arquivo, então somam os válidos
    sen <- v$cargos$senador
    soma_sen <- integer(length(v$municipios))
    for (p in sen$candidatos) {
      i <- p[c(TRUE, FALSE)] + 1
      soma_sen[i] <- soma_sen[i] + p[c(FALSE, TRUE)]
    }
    expect_equal(soma_sen, sen$validos, info = paste(uf, "senador"))
  }
  expect_equal(total_mun, 5571)
  expect_equal(length(ler_json(arq_votos("BR"))$municipios), 5571)
})

test_that("geometria de cada UF tem os mesmos municípios do arquivo de votos", {
  skip_if_not(file.exists(arq_votos("PE")))
  for (uf in c("PE", "MT", "DF", "SP")) {
    topo <- jsonlite::fromJSON(file.path(DIR_OUTPUT, "geo", sprintf("municipios_%s.topojson", uf)),
                               simplifyVector = FALSE)
    cods <- vapply(topo$objects$municipios$geometries, function(g) as.integer(g$properties$code_muni), integer(1))
    expect_setequal(cods, ler_json(arq_votos(uf))$municipios)
  }
})

test_that("candidatos do arquivo de votos são exatamente os exibidos da UF", {
  skip_if_not(file.exists(arq_votos("PE")))
  for (uf in c("PE", "SP", "AC")) {
    v <- ler_json(arq_votos(uf))
    cand <- ler_json(file.path(DIR_OUTPUT, "candidatos", paste0(uf, ".json")))
    sq_votos <- unlist(lapply(v$cargos, function(c) names(c$candidatos)))
    # senadores de 2022 estão no arquivo de candidatos (card), mas não têm
    # votos em 2026; candidatos ao Senado com 0 voto válido (candidatura
    # indeferida, votos anulados) também ficam só no arquivo de candidatos.
    com_voto <- vapply(cand, function(c) c$ano == ANO && isTRUE(c$votos > 0), logical(1))
    expect_setequal(sq_votos, names(cand)[com_voto])
  }
})
