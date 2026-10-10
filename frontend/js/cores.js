// Helpers de cor (herdados do painel-eleicoes-2026): interpolação branco ->
// cor para o modo contínuo, escurecer/clarear para o líder (margem alta/
// baixa) e paleta fixa do LISA.
const Cores = (() => {
  // "Não significante" muda por tema: no escuro, o cinza claro contrastava
  // demais contra o fundo; no claro, fica mais translúcido (ver clone).
  const PALETA_LISA = {
    escuro: { "Alto-Alto": "#d7191c", "Baixo-Baixo": "#2c7bb6", "Alto-Baixo": "#fdae61", "Baixo-Alto": "#abd9e9", "Não significante": "#4a4a4a" },
    claro: { "Alto-Alto": "#d7191c", "Baixo-Baixo": "#2c7bb6", "Alto-Baixo": "#fdae61", "Baixo-Alto": "#abd9e9", "Não significante": "#d4d4d4" },
  };
  const OPACIDADE_LISA_NS = { escuro: 0.9, claro: 0.5 };

  function hexParaRgb(hex) {
    const h = hex.replace("#", "");
    return { r: parseInt(h.substring(0, 2), 16), g: parseInt(h.substring(2, 4), 16), b: parseInt(h.substring(4, 6), 16) };
  }

  function rgbParaHex({ r, g, b }) {
    const canal = (v) => Math.round(v).toString(16).padStart(2, "0");
    return `#${canal(r)}${canal(g)}${canal(b)}`;
  }

  function misturar(corHex, alvo, t) {
    const c = hexParaRgb(corHex);
    const tc = Math.max(0, Math.min(1, t));
    return rgbParaHex({ r: c.r + (alvo.r - c.r) * tc, g: c.g + (alvo.g - c.g) * tc, b: c.b + (alvo.b - c.b) * tc });
  }

  // t em [0,1]: 0 = quase branco, 1 = cor cheia.
  function interpolarComBranco(corHex, t) {
    return misturar("#f5f5f5", hexParaRgb(corHex), t);
  }

  // t em [0,1]: 0 = cor cheia, 1 = quase preto.
  function escurecer(corHex, t) {
    return misturar(corHex, { r: 20, g: 20, b: 20 }, t);
  }

  function corLisa(cluster, tema) {
    return (PALETA_LISA[tema] || PALETA_LISA.escuro)[cluster] || "#cccccc";
  }

  function opacidadeLisa(cluster, tema) {
    return cluster === "Não significante" ? OPACIDADE_LISA_NS[tema] ?? 0.9 : 0.9;
  }

  return { interpolarComBranco, escurecer, corLisa, opacidadeLisa, PALETA_LISA };
})();
