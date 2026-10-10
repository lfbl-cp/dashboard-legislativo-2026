// Alternância de tema claro/escuro. Escuro é o padrão; a preferência é
// lembrada em localStorage (só conveniência -- sem ela, volta ao escuro).
const Tema = (() => {
  const CHAVE = "painel-legislativo-2026:tema";

  function lido() {
    try {
      return localStorage.getItem(CHAVE);
    } catch (e) {
      return null;
    }
  }

  function salvar(tema) {
    try {
      localStorage.setItem(CHAVE, tema);
    } catch (e) {
      // storage indisponível (aba privada, bloqueado) -- só não lembra.
    }
  }

  function aplicar(tema) {
    document.body.dataset.tema = tema;
    document.getElementById("btn-tema").textContent = tema === "escuro" ? "Escuro" : "Claro";
    Mapa.definirTema(tema);
    salvar(tema);
    document.dispatchEvent(new CustomEvent("tema-alterado", { detail: tema }));
  }

  function iniciar() {
    aplicar(lido() === "claro" ? "claro" : "escuro");
    document.getElementById("btn-tema").addEventListener("click", () => {
      aplicar(document.body.dataset.tema === "escuro" ? "claro" : "escuro");
    });
  }

  return { iniciar };
})();
