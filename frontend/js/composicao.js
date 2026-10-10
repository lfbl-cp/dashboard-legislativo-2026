// Aba Composição: hemiciclo da Casa escolhida (Câmara, Senado ou
// Assembleia de uma UF), agrupado por partido ou federação, com destaque de
// bancada estadual, destaque de grupo (clique na legenda) e card do eleito
// (clique na cadeira). Dados: output/composicao.json.
const Composicao = (() => {
  const HOSTS_REDES = {
    "instagram.com": "Instagram", "facebook.com": "Facebook", "fb.com": "Facebook",
    "tiktok.com": "TikTok", "twitter.com": "X/Twitter", "x.com": "X/Twitter",
    "youtube.com": "YouTube", "threads.com": "Threads", "threads.net": "Threads",
    "kwai.com": "Kwai", "linkedin.com": "LinkedIn", "linktr.ee": "Linktree",
  };

  let dados = null;
  let desenho = null; // retorno de Hemiciclo.desenhar()
  const estado = { casa: "camara", uf: "SP", destaque: "", agrupar: "partido", grupo: null, sq: null };
  let aoMudarEstado = () => {};

  const el = (id) => document.getElementById(id);

  function idCasa() {
    return estado.casa === "assembleia" ? `assembleia_${estado.uf}` : estado.casa;
  }

  // --- grupos (fatias do hemiciclo) ---------------------------------------
  function grupoDaCadeira(c) {
    const p = dados.partidos[c.sigla];
    if (estado.agrupar === "federacao" && p.federacao) {
      const f = dados.federacoes[p.federacao];
      return { chave: `F${p.federacao}`, rotulo: f.sigla, nome: f.nome, cor: f.cor, ideologia: f.ideologia };
    }
    return { chave: c.sigla, rotulo: p.rotulo, nome: null, cor: p.cor, ideologia: p.ideologia };
  }

  const ideologiaOrd = (v) => (v === null || v === undefined ? Infinity : v);

  function montarGrupos(cadeiras) {
    const porChave = new Map();
    cadeiras.forEach((c) => {
      const g = grupoDaCadeira(c);
      if (!porChave.has(g.chave)) porChave.set(g.chave, { ...g, cadeiras: [] });
      porChave.get(g.chave).cadeiras.push(c);
    });
    const grupos = [...porChave.values()].sort(
      (a, b) => ideologiaOrd(a.ideologia) - ideologiaOrd(b.ideologia) || a.rotulo.localeCompare(b.rotulo)
    );
    // Dentro do grupo: partidos da federação contíguos (esquerda->direita),
    // depois eleitos de 2026 antes dos de 2022 (Senado), UF e nome.
    grupos.forEach((g) => {
      g.cadeiras.sort((a, b) => {
        const pa = dados.partidos[a.sigla];
        const pb = dados.partidos[b.sigla];
        return (
          ideologiaOrd(pa.ideologia) - ideologiaOrd(pb.ideologia) ||
          a.sigla.localeCompare(b.sigla) ||
          b.ano - a.ano ||
          a.uf.localeCompare(b.uf) ||
          a.nome.localeCompare(b.nome)
        );
      });
    });
    return grupos;
  }

  // --- render ---------------------------------------------------------------
  function render() {
    const casa = dados.casas[idCasa()];
    const grupos = montarGrupos(casa.cadeiras);
    const ehSenado = estado.casa === "senado";

    el("label-uf-casa").hidden = estado.casa !== "assembleia";
    el("label-destaque").hidden = estado.casa === "assembleia";

    let titulo = casa.nome;
    if (estado.destaque && estado.casa !== "assembleia") {
      const n = casa.cadeiras.filter((c) => c.uf === estado.destaque).length;
      titulo += ` — bancada de ${NOMES_UF[estado.destaque]} (${n})`;
    }
    el("hemiciclo-titulo").textContent = titulo;
    el("hemiciclo-nota").textContent = ehSenado
      ? `Círculo cheio: eleito em ${dados.ano} (mandato até 2035). Vazado: eleito em ${dados.ano_senado_anterior} (mandato até 2031), pelo partido da eleição.`
      : "";

    desenho = Hemiciclo.desenhar(el("hemiciclo-svg"), grupos, {
      vazada: (c) => ehSenado && c.ano === dados.ano_senado_anterior,
    });
    desenho.circulos.forEach((item) => {
      item.el.addEventListener("mouseenter", (ev) => mostrarTooltip(ev, item));
      item.el.addEventListener("mousemove", posicionarTooltip);
      item.el.addEventListener("mouseleave", esconderTooltip);
      item.el.addEventListener("click", () => selecionar(item.cadeira.sq));
    });

    aplicarDestaques();
    renderLegenda(grupos, casa);
    renderCard();
    aoMudarEstado();
  }

  function apagada(item) {
    if (estado.destaque && estado.casa !== "assembleia" && item.cadeira.uf !== estado.destaque) return true;
    if (estado.grupo && item.grupo.chave !== estado.grupo) return true;
    return false;
  }

  function aplicarDestaques() {
    desenho.circulos.forEach((item) => item.el.classList.toggle("apagada", apagada(item)));
    desenho.marcar(desenho.circulos.find((item) => item.cadeira.sq === estado.sq) || null);
  }

  function renderLegenda(grupos, casa) {
    const cont = el("legenda-composicao");
    const filtroUf = estado.destaque && estado.casa !== "assembleia" ? estado.destaque : null;
    const conta = (lista) => (filtroUf ? lista.filter((c) => c.uf === filtroUf).length : lista.length);
    const total = conta(casa.cadeiras);

    let html = `<div class="legenda-cabecalho"><span>Esquerda → direita</span><span>${
      filtroUf ? `bancada ${filtroUf}` : "cadeiras"
    }</span></div>`;
    grupos.forEach((g) => {
      const n = conta(g.cadeiras);
      const classes = ["legenda-grupo"];
      if ((estado.grupo && estado.grupo !== g.chave) || n === 0) classes.push("apagado");
      let membros = "";
      if (g.chave.startsWith("F")) {
        const porPartido = {};
        g.cadeiras.forEach((c) => {
          if (!filtroUf || c.uf === filtroUf) porPartido[c.sigla] = (porPartido[c.sigla] || 0) + 1;
        });
        membros = `<span class="membros">${Object.entries(porPartido)
          .map(([s, k]) => `${Util.esc(dados.partidos[s].rotulo)} ${k}`)
          .join(" · ")}</span>`;
      }
      html += `<button type="button" class="${classes.join(" ")}" data-grupo="${Util.esc(g.chave)}"
        title="${Util.esc(g.nome || g.rotulo)}" aria-pressed="${estado.grupo === g.chave}">
        <span class="swatch" style="background:${g.cor}"></span>
        <span>${Util.esc(g.rotulo)}</span>
        <span class="n">${n}</span>
        <span class="pct">${total ? Util.pct(n / total) : ""}</span>
        ${membros}
      </button>`;
    });
    if (estado.grupo) {
      html += `<div class="legenda-acoes"><button type="button" class="link-botao" id="btn-limpar-grupo">Mostrar todos</button></div>`;
    }
    cont.innerHTML = html;

    cont.querySelectorAll(".legenda-grupo").forEach((b) => {
      b.addEventListener("click", () => {
        estado.grupo = estado.grupo === b.dataset.grupo ? null : b.dataset.grupo;
        aplicarDestaques();
        renderLegenda(grupos, casa);
        aoMudarEstado();
      });
    });
    const limpar = el("btn-limpar-grupo");
    if (limpar) {
      limpar.addEventListener("click", () => {
        estado.grupo = null;
        aplicarDestaques();
        renderLegenda(grupos, casa);
        aoMudarEstado();
      });
    }
  }

  // --- foto, tooltip e card ---------------------------------------------------
  function htmlIniciais(iniciais, cor) {
    return `<div class="foto-iniciais" style="background:${Util.esc(cor)}">${Util.esc(iniciais)}</div>`;
  }

  // Sem foto (ou se a imagem falhar ao carregar -- ver listener em
  // iniciar()), mostra as iniciais sobre a cor do partido.
  function htmlFoto(c, cor) {
    const ini = Util.iniciais(c.nome);
    if (!c.foto) return htmlIniciais(ini, cor);
    return `<img class="foto" src="${Dados.urlFoto(Util.esc(c.sq))}" alt="" loading="lazy"
      data-iniciais="${Util.esc(ini)}" data-cor="${Util.esc(cor)}">`;
  }

  function mostrarTooltip(ev, item) {
    const c = item.cadeira;
    const tip = el("tooltip");
    tip.innerHTML = `${htmlFoto(c, item.grupo.cor)}<div><b>${Util.esc(c.nome)}</b><br>${Util.esc(
      dados.partidos[c.sigla].rotulo
    )} · ${Util.esc(c.uf)}</div>`;
    tip.hidden = false;
    posicionarTooltip(ev);
  }

  function posicionarTooltip(ev) {
    const tip = el("tooltip");
    const x = Math.min(ev.clientX + 14, window.innerWidth - tip.offsetWidth - 8);
    const y = Math.min(ev.clientY + 14, window.innerHeight - tip.offsetHeight - 8);
    tip.style.left = `${x}px`;
    tip.style.top = `${y}px`;
  }

  function esconderTooltip() {
    el("tooltip").hidden = true;
  }

  function selecionar(sq) {
    estado.sq = estado.sq === sq ? null : sq;
    aplicarDestaques();
    renderCard();
    aoMudarEstado();
  }

  function situacao(c) {
    if (estado.casa === "senado") {
      return c.ano === dados.ano_senado_anterior
        ? `Eleito em ${c.ano} · mandato até 2031`
        : `Eleito em ${c.ano} · mandato até 2035`;
    }
    if (c.sit === "QP") return "Eleito por quociente partidário";
    if (c.sit === "média") return "Eleito por média";
    return "Eleito";
  }

  function rotuloRede(url) {
    const host = url.replace(/^[a-z]+:\/\//i, "").split(/[/?#]/)[0].toLowerCase();
    const conhecido = Object.keys(HOSTS_REDES).find((h) => host === h || host.endsWith(`.${h}`));
    return conhecido ? HOSTS_REDES[conhecido] : host.replace(/^www\./, "");
  }

  function renderCard() {
    const card = el("card-eleito");
    const c = estado.sq && dados.casas[idCasa()].cadeiras.find((x) => x.sq === estado.sq);
    if (!c) {
      card.hidden = true;
      card.innerHTML = "";
      return;
    }
    const p = dados.partidos[c.sigla];
    const f = p.federacao ? dados.federacoes[p.federacao] : null;
    const linhas = [
      ["UF", NOMES_UF[c.uf]],
      ["Idade", c.idade != null ? `${c.idade} anos` : null],
      ["Gênero", Util.capitalizar(c.genero)],
      ["Ocupação", Util.capitalizar(c.ocupacao)],
      ["Instrução", Util.capitalizar(c.instrucao)],
      ["Coligação", c.coligacao],
    ].filter(([, v]) => v);
    const redes = (c.redes || [])
      .filter((u) => /^https?:\/\//i.test(u))
      .map((u) => `<a href="${Util.esc(u)}" target="_blank" rel="noopener noreferrer">${Util.esc(rotuloRede(u))}</a>`)
      .join("");

    card.innerHTML = `
      <div class="card-topo">
        ${htmlFoto(c, p.cor)}
        <div>
          <p class="card-nome">${Util.esc(c.nome)}</p>
          <p class="card-sub">${Util.esc(c.nome_completo)}</p>
          <span class="card-partido"><span class="swatch" style="background:${p.cor}"></span>${Util.esc(p.rotulo)}</span>
          ${f ? `<div class="card-sub">${Util.esc(f.nome)}</div>` : ""}
          <div class="card-sub">${Util.esc(situacao(c))}</div>
        </div>
      </div>
      <dl class="card-dados">${linhas.map(([k, v]) => `<dt>${k}</dt><dd>${Util.esc(v)}</dd>`).join("")}</dl>
      ${redes ? `<div class="card-redes">${redes}</div>` : ""}
      <div class="legenda-acoes"><button type="button" class="link-botao" id="btn-fechar-card">Fechar</button></div>`;
    card.hidden = false;
    el("btn-fechar-card").addEventListener("click", () => selecionar(estado.sq));
  }

  // --- seletores --------------------------------------------------------------
  function popularSeletores() {
    el("sel-uf-casa").innerHTML = UFS.map((uf) => `<option value="${uf}">${NOMES_UF[uf]}</option>`).join("");
    el("sel-destaque").innerHTML =
      `<option value="">Todas as UFs</option>` + UFS.map((uf) => `<option value="${uf}">${NOMES_UF[uf]}</option>`).join("");
  }

  function sincronizarControles() {
    el("sel-casa").value = estado.casa;
    el("sel-uf-casa").value = estado.uf;
    el("sel-destaque").value = estado.destaque;
    el("seg-agrupar").querySelectorAll("button").forEach((b) => {
      b.setAttribute("aria-pressed", String(b.dataset.valor === estado.agrupar));
    });
  }

  function ligarControles() {
    el("sel-casa").addEventListener("change", (e) => {
      estado.casa = e.target.value;
      estado.grupo = null;
      estado.sq = null;
      render();
    });
    el("sel-uf-casa").addEventListener("change", (e) => {
      estado.uf = e.target.value;
      estado.grupo = null;
      estado.sq = null;
      render();
    });
    el("sel-destaque").addEventListener("change", (e) => {
      estado.destaque = e.target.value;
      render();
    });
    el("seg-agrupar").querySelectorAll("button").forEach((b) => {
      b.addEventListener("click", () => {
        if (estado.agrupar === b.dataset.valor) return;
        estado.agrupar = b.dataset.valor;
        estado.grupo = null;
        sincronizarControles();
        render();
      });
    });
  }

  // inicial: valores lidos da URL (validados aqui; inválido cai no padrão).
  async function iniciar(inicial, callbackEstado) {
    aoMudarEstado = callbackEstado || aoMudarEstado;
    dados = await Dados.carregarJson("output/composicao.json");
    if (["camara", "senado", "assembleia"].includes(inicial.casa)) estado.casa = inicial.casa;
    if (UFS.includes(inicial.uf)) estado.uf = inicial.uf;
    if (UFS.includes(inicial.destaque)) estado.destaque = inicial.destaque;
    if (["partido", "federacao"].includes(inicial.agrupar)) estado.agrupar = inicial.agrupar;
    el("fonte-ideologia").textContent = `Ordem esquerda → direita: ${dados.fonte_ideologia}.`;
    // Erro de <img> não borbulha; captura no documento troca qualquer foto
    // quebrada pelas iniciais.
    document.addEventListener("error", (ev) => {
      const img = ev.target;
      if (img instanceof HTMLImageElement && img.classList.contains("foto")) {
        img.outerHTML = htmlIniciais(img.dataset.iniciais, img.dataset.cor);
      }
    }, true);
    popularSeletores();
    sincronizarControles();
    ligarControles();
    render();
  }

  function estadoUrl() {
    return {
      casa: estado.casa,
      uf: estado.casa === "assembleia" ? estado.uf : "",
      destaque: estado.casa !== "assembleia" ? estado.destaque : "",
      agrupar: estado.agrupar === "partido" ? "" : estado.agrupar,
    };
  }

  return { iniciar, estadoUrl };
})();
