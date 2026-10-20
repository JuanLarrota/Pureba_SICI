// Frases, no fórmulas: lo que la pantalla escribe a partir de un número o un código.

export const titulo = (s?: string | null) => String(s || "").toLowerCase().replace(/(^|\s)(\S)/g, (m, a, b) => a + b.toUpperCase());
export const frase = (s: string) => (s ? s[0].toUpperCase() + s.slice(1) : s);
export const lista = (a: string[]) => (a.length < 2 ? a.join("") : a.slice(0, -1).join(", ") + " y " + a[a.length - 1]);
export const uno = (n: number, singular: string, plural: string) => (n === 1 ? singular : `${n} ${plural}`);
export const num = (n: number) => String(Math.round(n * 10) / 10).replace(".", ",");
export const enDias = (n0: number) => { const n = Math.round(n0 * 10) / 10; return n === 0.5 ? "medio día" : n === 1 ? "un día" : `${num(n)} días`; };
/** Cuánto trabajo pide una tarea, en días. Lo escoge quien la asigna. */
export const ESFUERZO: [number, string][] = [[0.3, "Un par de horas"], [0.5, "Medio día"], [1, "Un día"], [2, "Dos días"], [3, "Tres días"], [5, "Una semana"], [10, "Dos semanas"], [15, "Tres semanas"], [20, "Un mes"]];
export const esfuerzo = (n?: number | string | null) =>
  n == null ? "" : (ESFUERZO.find((e) => e[0] === Number(n)) || [0, enDias(Number(n)) + " de trabajo"])[1].toLowerCase();
export const pesos = (n?: number | string | null) => (n == null ? "sin valor" : (Number(n) < 0 ? "−$" : "$") + Math.abs(Math.round(Number(n))).toLocaleString("es-CO"));
/** «1.250.000» → 1250000 */
export const plata = (v?: string | number | null) => Math.round(Number(String(v ?? "").replace(/[^\d]/g, "")) || 0);
export const iniciales = (n?: string | null) => String(n || "").trim().split(/\s+/).map((x) => x[0]).slice(0, 2).join("").toUpperCase();
export const nombreCorto = (n?: string | null) => String(n || "").split(" ")[0];
export const nFase = (f?: string | null) => titulo(String(f || "").replace(/_/g, " "));
export const whatsapp = (t?: string | null) => { const d = String(t || "").replace(/\D/g, ""); return d ? `https://wa.me/${d.length === 10 ? "57" + d : d}` : ""; };
