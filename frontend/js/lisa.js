// LISA (Moran local) no navegador -- trazido do painel de Pernambuco
// (www/lisa.js, conferido lá contra o spdep por qa_lisa.html). Replica
// spdep::localmoran (spdep 1.4; conditional = TRUE, mlvar = TRUE,
// alternative = "two.sided") com pesos W (padronizados na linha) sobre a
// vizinhança queen exportada pelo pipeline (votos/{UF}.json, `vizinhos`), e a
// classificação por quadrante (sinal de z e da defasagem; p < alpha, senão
// "Não significante"). Conferido de novo aqui por tests/qa_frontend.R.
const LISA = (() => {
  const NIVEIS = ["Alto-Alto", "Baixo-Baixo", "Alto-Baixo", "Baixo-Alto", "Não significante"];
  const NS = "Não significante";
  // Nomes exibidos: tipologia de territórios eleitorais de Terron (2009). Os
  // códigos acima continuam internos (cores, QA contra o spdep).
  const NOMES = {
    "Alto-Alto": "Território forte",
    "Alto-Baixo": "Forte isolado",
    "Baixo-Baixo": "Território fraco",
    "Baixo-Alto": "Fraco isolado",
    "Não significante": "Não significante",
  };
  const nome = (nivel) => NOMES[nivel] || nivel;

  // 1 - Phi(x) via erfc (aproximação de Numerical Recipes, erro relativo
  // < 1,2e-7 -- folga enorme para o corte p < 0,05).
  function erfc(x) {
    const z = Math.abs(x);
    const t = 1 / (1 + 0.5 * z);
    const r = t * Math.exp(-z * z - 1.26551223 + t * (1.00002368 + t * (0.37409196 + t * (0.09678418 +
      t * (-0.18628806 + t * (0.27886807 + t * (-1.13520398 + t * (1.48851587 + t * (-0.82215223 +
      t * 0.17087277)))))))));
    return x >= 0 ? r : 2 - r;
  }
  const pBilateral = (zv) => erfc(Math.abs(zv) / Math.SQRT2);

  // valores: números por município (NaN/null -> 0); vizinhos: listas de
  // índices base 0. Devolve um rótulo de NIVEIS por município.
  function classificar(valores, vizinhos, alpha = 0.05) {
    const n = valores.length;
    const x = Array.from(valores, (v) => (v == null || !Number.isFinite(v) ? 0 : v));
    const naoSig = () => x.map(() => NS);
    if (n < 5 || !vizinhos || vizinhos.length !== n) return naoSig();
    if (vizinhos.every((v) => !v || v.length === 0)) return naoSig();
    const media = x.reduce((a, b) => a + b, 0) / n;
    const z = x.map((v) => v - media);
    const ss = z.reduce((a, b) => a + b * b, 0);
    if (!(ss > 0)) return naoSig();
    const m2 = ss / n; // mlvar = TRUE
    const out = new Array(n);
    for (let i = 0; i < n; i++) {
      const viz = vizinhos[i] || [];
      const k = viz.length;
      if (k === 0) {
        out[i] = NS;
        continue;
      }
      let lz = 0;
      for (let j = 0; j < k; j++) lz += z[viz[j]];
      lz /= k;
      const Wi = 1;
      const Wi2 = 1 / k; // pesos W: k pesos de 1/k
      const Ii = (z[i] / m2) * lz;
      const EIi = -(z[i] * z[i] * Wi) / ((n - 1) * m2);
      const VarIi = Math.pow(z[i] / m2, 2) * (n / (n - 2)) * (Wi2 - (Wi * Wi) / (n - 1)) * (m2 - (z[i] * z[i]) / (n - 1));
      const Zi = (Ii - EIi) / Math.sqrt(VarIi);
      let p = pBilateral(Zi);
      if (!Number.isFinite(p)) p = 1;
      if (p >= alpha) {
        out[i] = NS;
        continue;
      }
      out[i] = z[i] >= 0 ? (lz >= 0 ? "Alto-Alto" : "Alto-Baixo") : lz < 0 ? "Baixo-Baixo" : "Baixo-Alto";
    }
    return out;
  }

  return { NIVEIS, NS, NOMES, nome, classificar };
})();
