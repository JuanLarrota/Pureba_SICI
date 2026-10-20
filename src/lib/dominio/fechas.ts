// Fechas en el formato de la base (ISO «AAAA-MM-DD») y su lectura en español.

export const MESES = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre", "noviembre", "diciembre"];
export const SEMANA = ["domingo", "lunes", "martes", "miércoles", "jueves", "viernes", "sábado"];

export const fecha = (iso?: string | null): string => {
  if (!iso) return "sin fecha";
  const [a, m, d] = String(iso).slice(0, 10).split("-");
  void a;
  return `${+d} de ${MESES[+m - 1]}`;
};
export const hora = (iso: string) => new Date(iso).toLocaleString("es-CO", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" });
export const hoyIso = () => new Date(Date.now() - new Date().getTimezoneOffset() * 60000).toISOString().slice(0, 10);
export const ahoraLocal = () => new Date(Date.now() - new Date().getTimezoneOffset() * 60000).toISOString().slice(0, 16);
/** Días desde 1970 (número de día), para comparar y restar fechas ISO. */
export const dia0 = (iso: string) => Date.UTC(+iso.slice(0, 4), +iso.slice(5, 7) - 1, +iso.slice(8, 10)) / 864e5;
export const isoDe = (n: number) => new Date(n * 864e5).toISOString().slice(0, 10);
export const lunesDe = (iso: string) => { const n = dia0(iso); return isoDe(n - (new Date(n * 864e5).getUTCDay() + 6) % 7); };
export const corta = (iso: string) => `${+iso.slice(8, 10)} ${MESES[+iso.slice(5, 7) - 1].slice(0, 3)}`;
export const mesLargo = (iso: string) => `${MESES[+iso.slice(5, 7) - 1][0].toUpperCase()}${MESES[+iso.slice(5, 7) - 1].slice(1)} de ${iso.slice(0, 4)}`;
export const momento = (iso: string) => `${fecha(iso)}, ${new Date(iso).toLocaleTimeString("es-CO", { hour: "numeric", minute: "2-digit" })}`;
export const enCuanto = (iso: string) => {
  const d = dia0(iso) - dia0(hoyIso());
  return d === 0 ? "hoy" : d === 1 ? "mañana" : d > 1 ? `en ${d} días` : d === -1 ? "desde ayer" : `hace ${-d} días`;
};
export const diaSemana = (iso: string) => SEMANA[new Date(dia0(iso) * 864e5).getUTCDay()];
