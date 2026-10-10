// Hemiciclo em SVG, sem biblioteca. Layout clássico de diagrama
// parlamentar: cadeiras em arcos concêntricos (semicírculos), distribuídas
// pelas fileiras em proporção ao comprimento de cada arco; depois as
// posições são ordenadas por ângulo (da esquerda para a direita) e
// preenchidas na ordem dos grupos -- cada partido vira uma "fatia".
const Hemiciclo = (() => {
  const SVG_NS = "http://www.w3.org/2000/svg";

  // Raio interno relativo (o externo é 1): o miolo vazio abriga o total.
  function raioInterno(n) {
    return n <= 30 ? 0.45 : 0.4;
  }

  // Capacidade de cada fileira para um espaçamento h entre cadeiras
  // (igual ao espaçamento entre fileiras): ~ comprimento do arco / h.
  function capacidades(h, ri) {
    const fileiras = Math.max(1, Math.floor((1 - ri) / h + 1e-9) + 1);
    const caps = [];
    for (let k = 0; k < fileiras; k++) {
      const r = 1 - k * h;
      caps.push(Math.floor((Math.PI * r) / h) + 1);
    }
    return caps;
  }

  const soma = (v) => v.reduce((a, b) => a + b, 0);

  // Posições de n cadeiras: [{x, y, ang, r}], já ordenadas da esquerda para
  // a direita, mais o raio de desenho de cada cadeira.
  function layout(n) {
    const ri = raioInterno(n);
    // Maior espaçamento (cadeiras maiores) que ainda acomoda as n cadeiras.
    let lo = 0.004;
    let hi = 0.6;
    for (let i = 0; i < 60; i++) {
      const meio = (lo + hi) / 2;
      if (soma(capacidades(meio, ri)) >= n) lo = meio;
      else hi = meio;
    }
    const h = lo;
    const caps = capacidades(h, ri);

    // Distribui n pelas fileiras em proporção à capacidade (maiores restos),
    // sem passar da capacidade de nenhuma.
    const total = soma(caps);
    const cotas = caps.map((c) => (n * c) / total);
    const alocadas = cotas.map((q, k) => Math.min(caps[k], Math.floor(q)));
    const ordemResto = cotas.map((q, k) => [q - Math.floor(q), k]).sort((a, b) => b[0] - a[0]);
    let faltam = n - soma(alocadas);
    for (let i = 0; faltam > 0; i = (i + 1) % ordemResto.length) {
      const k = ordemResto[i][1];
      if (alocadas[k] < caps[k]) {
        alocadas[k] += 1;
        faltam -= 1;
      }
    }

    const pontos = [];
    alocadas.forEach((m, k) => {
      const r = 1 - k * h;
      for (let j = 0; j < m; j++) {
        const ang = m === 1 ? Math.PI / 2 : Math.PI * (1 - j / (m - 1));
        pontos.push({ x: r * Math.cos(ang), y: -r * Math.sin(ang), ang, r });
      }
    });
    // Esquerda -> direita; no mesmo ângulo, de fora para dentro.
    pontos.sort((a, b) => b.ang - a.ang || b.r - a.r);
    return { pontos, raio: h * 0.42 };
  }

  function elemento(tag, attrs, pai) {
    const el = document.createElementNS(SVG_NS, tag);
    Object.entries(attrs).forEach(([k, v]) => el.setAttribute(k, v));
    if (pai) pai.appendChild(el);
    return el;
  }

  // grupos: [{chave, cor, cadeiras: [cadeira]}] já na ordem esquerda->direita.
  // opcoes.vazada(cadeira): desenha só o contorno (ex.: senador de 2022).
  // Devolve {circulos: [{el, cadeira, grupo, x, y}] na ordem dos grupos,
  // marcar(item)} -- marcar() põe o anel de seleção numa cadeira.
  function desenhar(svg, grupos, { vazada = () => false, legendaCentro = "" } = {}) {
    svg.innerHTML = "";
    const n = soma(grupos.map((g) => g.cadeiras.length));
    const { pontos, raio } = layout(n);
    // Margem cobre o raio das cadeiras da borda e o anel de seleção, inclusive
    // na fileira de baixo (centros em y = 0).
    const margem = raio * 2;
    svg.setAttribute("viewBox", `${-1 - margem} ${-1 - margem} ${2 + 2 * margem} ${1 + 2 * margem}`);
    svg.setAttribute("preserveAspectRatio", "xMidYMid meet");
    // Casas pequenas (24 a ~100 cadeiras) ocupariam a mesma largura que a
    // Câmara com cadeiras enormes; limita a largura conforme o tamanho.
    svg.style.maxWidth = n <= 30 ? "640px" : n <= 100 ? "860px" : "";

    const camada = elemento("g", {}, svg);
    const circulos = [];
    let i = 0;
    grupos.forEach((g) => {
      g.cadeiras.forEach((c) => {
        const p = pontos[i++];
        const oco = vazada(c);
        const circ = elemento("circle", {
          cx: p.x.toFixed(4),
          cy: p.y.toFixed(4),
          r: (oco ? raio * 0.78 : raio).toFixed(4),
          class: "cadeira",
          fill: oco ? "none" : g.cor,
          stroke: oco ? g.cor : "none",
          "stroke-width": oco ? (raio * 0.42).toFixed(4) : 0,
        }, camada);
        circulos.push({ el: circ, cadeira: c, grupo: g, x: p.x, y: p.y });
      });
    });
    // Anel de seleção, reposicionado por marcar(); fica por cima de tudo.
    const marcador = elemento("circle", { r: (raio * 1.45).toFixed(4), class: "marcador",
                                          "stroke-width": (raio * 0.35).toFixed(4), visibility: "hidden" }, svg);

    const maioria = Math.floor(n / 2) + 1;
    const total = elemento("text", { x: 0, y: -0.1, class: "centro-total", "font-size": 0.2 }, svg);
    total.textContent = n.toLocaleString("pt-BR");
    const sub = elemento("text", { x: 0, y: -0.02, class: "centro-legenda", "font-size": 0.05 }, svg);
    sub.textContent = legendaCentro || `cadeiras · maioria: ${maioria}`;

    // item = um dos `circulos` (ou null para esconder o anel).
    function marcar(item) {
      if (!item) {
        marcador.setAttribute("visibility", "hidden");
        return;
      }
      marcador.setAttribute("cx", item.x.toFixed(4));
      marcador.setAttribute("cy", item.y.toFixed(4));
      marcador.setAttribute("visibility", "visible");
    }

    return { circulos, marcar };
  }

  return { layout, desenhar };
})();
