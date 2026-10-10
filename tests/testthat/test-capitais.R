arq_capital <- function(uf) file.path(DIR_OUTPUT, "capitais", paste0(uf, ".json"))

test_that("votos por seção: nominal, legenda, branco, nulo, nulo técnico e anulado", {
  v <- data.table::data.table(
    nr_zona = 1L, nr_local = 10L, cd_cargo = 6L,
    sq_candidato = c("1", "2", "3", "-3", "-3", "-3", "-1", "-1"),
    nr_votavel = c(1311L, 4422L, 2244L, 13L, 44L, 22L, 95L, 96L),
    votos = c(10L, 5L, 3L, 2L, 1L, 7L, 4L, 6L)
  )
  cand <- data.frame(ano = ANO, cargo = "federal", sq_candidato = c("1", "2", "3"), sigla = c("PT", "UNIAO", "PL"))
  part <- data.frame(sigla = c("PT", "UNIAO", "PL"), nr_2026 = c(13L, 44L, 22L))
  # sq 1: válido; sq 2: presente com 0 (anulado sub judice); sq 3: ausente
  # do munzona (nulo técnico). Legenda sem voto válido segue o partido:
  # UNIAO tem legenda anulada sub judice no munzona -> anulada; PL -> nulo técnico.
  val <- list(candidatos = "1", presentes = c("1", "2"), partidos = "federal PT", legenda_subjud = "federal UNIAO")
  r <- classificar_votos_secao(v, cand, part, val)
  expect_equal(r$tipo, c("nominal", "anulado", "nulo", "legenda", "anulado", "nulo", "branco", "nulo"))
  expect_equal(r$sigla, c("PT", NA, NA, "PT", NA, NA, NA, NA))
  expect_equal(r$cargo, rep("federal", 8))
})

test_that("arquivo de cada capital fecha por local e casa com a geometria", {
  skip_if_not(file.exists(arq_capital("PE")), "rode o pipeline (etapa capitais) antes")
  indice <- jsonlite::fromJSON(file.path(DIR_OUTPUT, "capitais", "index.json"), simplifyVector = FALSE)
  expect_setequal(names(indice), UFS_BRASIL)
  for (uf in UFS_BRASIL) {
    cap <- jsonlite::fromJSON(arq_capital(uf), simplifyVector = TRUE)
    n <- length(cap$locais$nome)
    expect_equal(n, indice[[uf]]$n_locais, info = uf)
    expect_equal(cap$code_muni, CAPITAIS[[uf]], info = uf)
    for (col in c("endereco", "bairro", "lat", "lon", "subdiv", "secoes")) expect_length(cap$locais[[col]], n)
    expect_length(cap$aptos, n)
    for (cg in c("federal", "estadual", "senador")) {
      c <- cap$cargos[[cg]]
      expect_equal(Reduce(`+`, c$partidos), c$validos, info = paste(uf, cg))
      # cada eleitor vota uma vez em cada cargo proporcional; no Senado (2
      # votos) o comparecimento é a metade dos votos do cargo
      votos <- c$validos + c$brancos + c$nulos
      expect_true(all(votos <= cap$comparecimento * if (cg == "senador") 2 else 1), info = paste(uf, cg))
      idx <- unlist(lapply(c$candidatos, function(p) p[c(TRUE, FALSE)]))
      expect_true(all(idx >= 0 & idx < n), info = paste(uf, cg))
    }
    ns <- indice[[uf]]$n_subdivisoes
    if (ns > 0) {
      expect_true(all(cap$locais$subdiv >= -1 & cap$locais$subdiv < ns), info = uf)
      expect_length(cap$vizinhos, ns)
      topo <- jsonlite::fromJSON(file.path(DIR_OUTPUT, "geo", sprintf("subdivisoes_%s.topojson", uf)),
                                 simplifyVector = FALSE)
      i <- vapply(topo$objects$subdivisoes$geometries, function(g) as.integer(g$properties$i), integer(1))
      expect_equal(sort(i), seq_len(ns) - 1L, info = uf)
    } else {
      expect_true(all(cap$locais$subdiv == -1), info = uf)
      expect_false(file.exists(file.path(DIR_OUTPUT, "geo", sprintf("subdivisoes_%s.topojson", uf))))
    }
  }
})
