// Utilidades compartilhadas: nomes de UF, escape de HTML, formatação,
// estado na URL (#aba=...&casa=...).
const NOMES_UF = {
  AC: "Acre", AL: "Alagoas", AM: "Amazonas", AP: "Amapá", BA: "Bahia",
  CE: "Ceará", DF: "Distrito Federal", ES: "Espírito Santo", GO: "Goiás",
  MA: "Maranhão", MG: "Minas Gerais", MS: "Mato Grosso do Sul",
  MT: "Mato Grosso", PA: "Pará", PB: "Paraíba", PE: "Pernambuco",
  PI: "Piauí", PR: "Paraná", RJ: "Rio de Janeiro",
  RN: "Rio Grande do Norte", RO: "Rondônia", RR: "Roraima",
  RS: "Rio Grande do Sul", SC: "Santa Catarina", SE: "Sergipe",
  SP: "São Paulo", TO: "Tocantins",
};
const UFS = Object.keys(NOMES_UF);

const Util = (() => {
  const ESCAPES = { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" };

  // Todo texto vindo dos dados passa por aqui antes de virar innerHTML.
  function esc(texto) {
    return String(texto ?? "").replace(/[&<>"']/g, (c) => ESCAPES[c]);
  }

  // x é fração (0-1): pct(0.1234) -> "12,3%".
  function pct(x, casas = 1) {
    return `${(100 * x).toLocaleString("pt-BR", { minimumFractionDigits: casas, maximumFractionDigits: casas })}%`;
  }

  // Diferença entre frações em pontos percentuais: pp(0.05) -> "5,0 p.p.".
  function pp(x) {
    return `${(100 * x).toLocaleString("pt-BR", { minimumFractionDigits: 1, maximumFractionDigits: 1 })} p.p.`;
  }

  function iniciais(nome) {
    const partes = String(nome || "").split(/\s+/).filter((p) => p.length > 2 || /^[A-ZÀ-Ú]/.test(p));
    return ((partes[0] || "")[0] || "").concat((partes.length > 1 ? partes[partes.length - 1][0] : "") || "").toUpperCase();
  }

  // "MASCULINO" -> "Masculino"; "SUPERIOR COMPLETO" -> "Superior completo".
  function capitalizar(texto) {
    if (!texto) return "";
    const t = String(texto).toLowerCase();
    return t.charAt(0).toUpperCase() + t.slice(1);
  }

  // --- estado na URL: o link compartilhado abre na mesma visão ------------
  function lerEstado() {
    const params = new URLSearchParams(location.hash.replace(/^#/, ""));
    return Object.fromEntries(params.entries());
  }

  function gravarEstado(estado) {
    const params = new URLSearchParams();
    Object.entries(estado).forEach(([k, v]) => {
      if (v !== undefined && v !== null && v !== "") params.set(k, v);
    });
    history.replaceState(null, "", `#${params.toString()}`);
  }

  return { esc, pct, pctBr: pct, pp, iniciais, capitalizar, lerEstado, gravarEstado };
})();
