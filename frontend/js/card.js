// Card do candidato, compartilhado pelo hemiciclo e pelo mapa. Os dados de
// card vêm de output/candidatos/{UF}.json, carregado só no primeiro clique
// num candidato daquela UF (cacheado por Dados.carregarJson).
const Card = (() => {
  const HOSTS_REDES = {
    "instagram.com": "Instagram", "facebook.com": "Facebook", "fb.com": "Facebook",
    "tiktok.com": "TikTok", "twitter.com": "X/Twitter", "x.com": "X/Twitter",
    "youtube.com": "YouTube", "threads.com": "Threads", "threads.net": "Threads",
    "kwai.com": "Kwai", "linkedin.com": "LinkedIn", "linktr.ee": "Linktree",
  };
  const ROTULO_CARGO = { federal: "Deputado Federal", estadual: "Deputado Estadual", senador: "Senador" };

  function htmlIniciais(iniciais, cor) {
    return `<div class="foto-iniciais" style="background:${Util.esc(cor)}">${Util.esc(iniciais)}</div>`;
  }

  // Sem foto (ou se a imagem falhar -- ver instalarFallbackFotos), mostra as
  // iniciais sobre a cor do partido. `c` precisa de sq, nome e foto.
  function htmlFoto(c, cor) {
    const ini = Util.iniciais(c.nome);
    if (!c.foto) return htmlIniciais(ini, cor);
    return `<img class="foto" src="${Dados.urlFoto(Util.esc(c.sq))}" alt="" loading="lazy"
      data-iniciais="${Util.esc(ini)}" data-cor="${Util.esc(cor)}">`;
  }

  // Erro de <img> não borbulha; captura no documento troca qualquer foto
  // quebrada pelas iniciais. Chamar uma vez.
  function instalarFallbackFotos() {
    document.addEventListener("error", (ev) => {
      const img = ev.target;
      if (img instanceof HTMLImageElement && img.classList.contains("foto")) {
        img.outerHTML = htmlIniciais(img.dataset.iniciais, img.dataset.cor);
      }
    }, true);
  }

  function rotuloRede(url) {
    const host = url.replace(/^[a-z]+:\/\//i, "").split(/[/?#]/)[0].toLowerCase();
    const conhecido = Object.keys(HOSTS_REDES).find((h) => host === h || host.endsWith(`.${h}`));
    return conhecido ? HOSTS_REDES[conhecido] : host.replace(/^www\./, "");
  }

  function situacao(c, meta) {
    if (c.cargo === "senador") {
      if (c.ano === meta.ano_senado_anterior) return `Eleito em ${c.ano} · mandato até 2031`;
      if (c.situacao === "eleito") return `Eleito em ${c.ano} · mandato até 2035`;
      return c.situacao === "nao_eleito" ? "Não eleito" : "Sem totalização";
    }
    if (c.situacao === "eleito") {
      if (c.sit === "QP") return "Eleito por quociente partidário";
      if (c.sit === "média") return "Eleito por média";
      return "Eleito";
    }
    if (c.situacao === "suplente") return c.ordem_suplente ? `${c.ordem_suplente}º suplente` : "Suplente";
    return "Não eleito";
  }

  async function dadosCandidato(sq, uf) {
    const lista = await Dados.carregarJson(`output/candidatos/${uf}.json`);
    const c = lista[sq];
    return c ? { sq, uf, ...c } : null;
  }

  // Renderiza o card de `sq` (da UF `uf`) em `container`. `aoFechar` liga o
  // botão Fechar; `aoVerNoMapa(c)`, se dado, mostra o botão "Ver no mapa"
  // (só para quem tem votos nesta eleição). Ignora respostas que chegam
  // depois de outro clique. Um contador por contêiner (hemiciclo e mapa
  // têm cards independentes).
  const pedidos = new WeakMap();
  async function renderizar(container, { sq, uf, meta, aoFechar, aoVerNoMapa }) {
    const pedido = (pedidos.get(container) || 0) + 1;
    pedidos.set(container, pedido);
    const pedidoAtual = () => pedidos.get(container);
    if (!sq) {
      container.hidden = true;
      container.innerHTML = "";
      return;
    }
    container.hidden = false;
    container.innerHTML = `<p class="aviso">Carregando…</p>`;
    let c;
    try {
      c = await dadosCandidato(sq, uf);
    } catch (e) {
      if (pedido === pedidoAtual()) container.innerHTML = `<p class="aviso">Erro ao carregar o candidato.</p>`;
      return;
    }
    if (pedido !== pedidoAtual()) return;
    if (!c) {
      container.innerHTML = `<p class="aviso">Candidato não encontrado.</p>`;
      return;
    }
    const p = meta.partidos[c.sigla];
    const f = p.federacao ? meta.federacoes[p.federacao] : null;
    const linhas = [
      ["Cargo", `${ROTULO_CARGO[c.cargo]} · ${NOMES_UF[c.uf]}`],
      ["Votos", c.votos != null && c.ano === meta.ano ? c.votos.toLocaleString("pt-BR") : null],
      ["Número", c.numero],
      ["Idade", c.idade != null ? `${c.idade} anos` : null],
      ["Gênero", Util.capitalizar(c.genero)],
      ["Ocupação", Util.capitalizar(c.ocupacao)],
      ["Instrução", Util.capitalizar(c.instrucao)],
      ["Coligação", c.coligacao],
    ].filter(([, v]) => v !== null && v !== undefined && v !== "");
    const redes = (c.redes || [])
      .filter((u) => /^https?:\/\//i.test(u))
      .map((u) => `<a href="${Util.esc(u)}" target="_blank" rel="noopener noreferrer">${Util.esc(rotuloRede(u))}</a>`)
      .join("");

    container.innerHTML = `
      <div class="card-topo">
        ${htmlFoto(c, p.cor)}
        <div>
          <p class="card-nome">${Util.esc(c.nome)}</p>
          <p class="card-sub">${Util.esc(c.nome_completo)}</p>
          <span class="card-partido"><span class="swatch" style="background:${Util.esc(p.cor)}"></span>${Util.esc(p.rotulo)}</span>
          ${f ? `<div class="card-sub">${Util.esc(f.nome)}</div>` : ""}
          <div class="card-sub">${Util.esc(situacao(c, meta))}</div>
        </div>
      </div>
      <dl class="card-dados">${linhas.map(([k, v]) => `<dt>${k}</dt><dd>${Util.esc(v)}</dd>`).join("")}</dl>
      ${redes ? `<div class="card-redes">${redes}</div>` : ""}
      <div class="legenda-acoes">
        ${aoVerNoMapa && c.ano === meta.ano ? `<button type="button" class="link-botao" data-acao="mapa">Ver no mapa</button>` : ""}
        ${aoFechar ? `<button type="button" class="link-botao" data-acao="fechar">Fechar</button>` : ""}
      </div>`;
    if (aoFechar) container.querySelector('[data-acao="fechar"]').addEventListener("click", aoFechar);
    const verMapa = container.querySelector('[data-acao="mapa"]');
    if (verMapa) verMapa.addEventListener("click", () => aoVerNoMapa(c));
  }

  return { htmlFoto, instalarFallbackFotos, renderizar };
})();
