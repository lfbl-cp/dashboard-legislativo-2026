# =============================================================================
# Candidatos: leitura do consulta_cand (27 UFs), situação final e quem aparece
# no painel por candidato (`exibir`): senador, todos; deputados, só eleitos e
# suplentes. Os totais de partido (Fase 3) somam todos, não só os exibidos.
# =============================================================================

# Só as colunas usadas. O consulta_cand traz CPF, e-mail e título de eleitor
# -- ficam de fora já na leitura, nunca entram no pipeline.
COLUNAS_CANDIDATO <- c(
  "ANO_ELEICAO", "NR_TURNO", "SG_UF", "CD_CARGO", "DS_CARGO", "SQ_CANDIDATO",
  "NR_CANDIDATO", "NM_CANDIDATO", "NM_URNA_CANDIDATO", "NR_PARTIDO", "SG_PARTIDO",
  "NR_FEDERACAO", "NM_FEDERACAO", "SG_FEDERACAO", "NM_COLIGACAO",
  "DS_COMPOSICAO_COLIGACAO", "DT_NASCIMENTO", "DS_GENERO", "DS_GRAU_INSTRUCAO",
  "DS_COR_RACA", "DS_OCUPACAO", "DS_SIT_TOT_TURNO"
)

# Conectivos que ficam minúsculos ao normalizar nome (exceto 1ª palavra).
CONECTIVOS_NOME_MINUSCULOS <- c("de", "da", "do", "das", "dos", "e")

# "RAQUEL LYRA" -> "Raquel Lyra" (o TSE manda nome de urna em CAIXA ALTA).
normalizar_nome_candidato <- function(nome) {
  vapply(nome, function(n) {
    if (is.na(n)) return(NA_character_)
    palavras <- strsplit(tolower(trimws(n)), " +")[[1]]
    palavras <- vapply(seq_along(palavras), function(i) {
      p <- palavras[i]
      if (i > 1 && p %in% CONECTIVOS_NOME_MINUSCULOS) return(p)
      paste0(toupper(substr(p, 1, 1)), substr(p, 2, nchar(p)))
    }, character(1))
    paste(palavras, collapse = " ")
  }, character(1), USE.NAMES = FALSE)
}

# DS_SIT_TOT_TURNO -> eleito / suplente / nao_eleito / NA. Observado em 2026:
# ELEITO, ELEITO POR QP, ELEITO POR MÉDIA, SUPLENTE, NÃO ELEITO e ausente
# (candidatura sem totalização -- indeferida, renúncia, sub judice).
classificar_situacao <- function(ds_sit_tot_turno) {
  s <- toupper(chartr("ÁÃÉÊÍÓÔÕÚÇ", "AAEEIOOOUC", ds_sit_tot_turno))
  dplyr::case_when(
    grepl("^ELEITO", s) ~ "eleito",
    grepl("SUPLENTE", s) ~ "suplente",
    grepl("^NAO ELEITO", s) ~ "nao_eleito",
    TRUE ~ NA_character_
  )
}

# Lê os candidatos dos cargos do painel (1º turno) de todas as UFs de um ano.
ler_candidatos <- function(ano) {
  csvs <- obter_csvs_candidatos(ano)
  x <- data.table::rbindlist(lapply(csvs, ler_csv_tse, select = COLUNAS_CANDIDATO))
  x <- x[NR_TURNO == TURNO & CD_CARGO %in% CARGOS$cd_cargo]
  # Uma linha por candidatura (o TSE repete candidato em raros casos de
  # retificação).
  unique(x, by = "SQ_CANDIDATO")
}

# Tabela de candidatos do painel a partir do consulta_cand cru.
montar_candidatos <- function(cand_raw) {
  cargos <- CARGOS[match(cand_raw$CD_CARGO, CARGOS$cd_cargo), ]
  dt_nasc <- as.Date(cand_raw$DT_NASCIMENTO, format = "%d/%m/%Y")
  data_eleicao <- if (cand_raw$ANO_ELEICAO[1] == ANO) DATA_ELEICAO else
    as.Date(sprintf("%d-10-02", cand_raw$ANO_ELEICAO[1]))
  out <- data.frame(
    ano = cand_raw$ANO_ELEICAO,
    uf = cand_raw$SG_UF,
    cargo = cargos$id,
    tipo = cargos$tipo,
    sq_candidato = as.character(cand_raw$SQ_CANDIDATO),
    nr_candidato = cand_raw$NR_CANDIDATO,
    nome = normalizar_nome_candidato(cand_raw$NM_URNA_CANDIDATO),
    nome_completo = normalizar_nome_candidato(cand_raw$NM_CANDIDATO),
    sigla = cand_raw$SG_PARTIDO,
    nr_partido = cand_raw$NR_PARTIDO,
    nr_federacao = ifelse(is.na(cand_raw$NR_FEDERACAO) | cand_raw$NR_FEDERACAO < 0,
                          NA_integer_, as.integer(cand_raw$NR_FEDERACAO)),
    # "FEDERAÇÃO" é o que o TSE põe em NM_COLIGACAO de quem concorreu por
    # federação -- não é coligação; a federação já aparece em nr_federacao.
    coligacao = ifelse(cand_raw$NM_COLIGACAO %in% c("PARTIDO ISOLADO", "FEDERAÇÃO", NA),
                       NA_character_, cand_raw$NM_COLIGACAO),
    situacao = classificar_situacao(cand_raw$DS_SIT_TOT_TURNO),
    ds_situacao_tse = cand_raw$DS_SIT_TOT_TURNO,
    genero = cand_raw$DS_GENERO,
    idade = as.integer(floor(as.numeric(data_eleicao - dt_nasc) / 365.25)),
    instrucao = cand_raw$DS_GRAU_INSTRUCAO,
    cor_raca = cand_raw$DS_COR_RACA,
    ocupacao = cand_raw$DS_OCUPACAO,
    stringsAsFactors = FALSE
  )
  out$exibir <- out$cargo == "senador" | out$situacao %in% c("eleito", "suplente")
  out
}

# Redes em que o identificador não diferencia maiúsculas e a query string é
# só rastreamento (?igsh=, ?s=, ?_t=...) -- nelas a URL é normalizada para
# minúsculas e sem query.
HOSTS_REDES <- c("instagram.com", "facebook.com", "fb.com", "tiktok.com", "twitter.com",
                 "x.com", "youtube.com", "threads.com", "threads.net", "kwai.com",
                 "linkedin.com", "linktr.ee")
MAX_REDES <- 6

# Normaliza a URL declarada (o TSE traz URLs em CAIXA ALTA, sem esquema, com
# parâmetros de rastreamento) e diz se é de uma rede conhecida.
limpar_url_rede <- function(url) {
  u <- trimws(url)
  u <- ifelse(grepl("^[a-zA-Z][a-zA-Z0-9+.-]*://", u), u, paste0("https://", u))
  partes <- regmatches(u, regexec("^([^:]+)://([^/?#]+)([^?#]*)(.*)$", u))
  vapply(partes, function(p) {
    if (length(p) == 0) return(NA_character_)
    host <- tolower(p[3])
    caminho <- p[4]
    conhecida <- any(host == HOSTS_REDES | endsWith(host, paste0(".", HOSTS_REDES)))
    if (conhecida) {
      caminho <- sub("/+$", "", tolower(caminho))
      return(paste0("https://", host, caminho))
    }
    paste0(tolower(p[2]), "://", host, caminho, p[5])
  }, character(1))
}

eh_rede_conhecida <- function(url) {
  host <- tolower(sub("^[^:]+://([^/?#]+).*$", "\\1", url))
  host %in% HOSTS_REDES | Reduce(`|`, lapply(paste0(".", HOSTS_REDES), endsWith, x = host))
}

# Redes sociais declaradas, só dos candidatos exibidos -> lista por candidato
# (até MAX_REDES, redes conhecidas primeiro, sem duplicatas).
montar_redes <- function(ano, sq_exibidos) {
  csvs <- obter_csvs_redes(ano)
  r <- data.table::rbindlist(lapply(csvs, ler_csv_tse,
                                    select = c("SQ_CANDIDATO", "NR_ORDEM_REDE_SOCIAL", "DS_URL")))
  r[, sq := as.character(SQ_CANDIDATO)]
  r <- r[sq %in% sq_exibidos & !is.na(DS_URL) & nzchar(trimws(DS_URL))]
  r[, url := limpar_url_rede(DS_URL)]
  r <- r[!is.na(url)]
  r[, conhecida := eh_rede_conhecida(url)]
  r <- unique(r[order(sq, -conhecida, NR_ORDEM_REDE_SOCIAL)], by = c("sq", "url"))
  r <- r[, head(.SD, MAX_REDES), by = sq]
  split(r$url, r$sq)
}
