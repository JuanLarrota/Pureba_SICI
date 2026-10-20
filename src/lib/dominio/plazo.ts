// Lo que se calcula en la pantalla a partir de lo que la base ya dijo: cuánto le
// falta a una tarea, cuánto le queda libre a una persona, cómo va una fase.
// Sigue a legado/app/app.js (la versión que Felipe revisó el 19-10).
import { corta, dia0, hoyIso, lunesDe } from "./fechas";
import { enDias } from "./texto";

export interface ConPlazo {
  fecha_compromiso?: string | null;
  fecha_inicio?: string | null;
  creada_en?: string | null;
  terminada_en?: string | null;
  estado?: string | null;
}
/** h = terminada · n = sin fecha · r = en revisión · c = vencida · a = por vencer (dos días hábiles o menos) · "" = a tiempo */
export type ClavePlazo = "h" | "n" | "r" | "c" | "a" | "";

/** Días hábiles (lunes a viernes) que quedan de mañana hasta la entrega, incluida. Negativo si b es antes. */
export const habiles = (desde: number, hasta: number): number => {
  if (hasta < desde) return -habiles(hasta, desde);
  let n = 0;
  for (let d = desde + 1; d <= hasta; d++) { const s = new Date(d * 864e5).getUTCDay(); if (s && s < 6) n++; }
  return n;
};

/** Cómo va el plazo de una tarea: qué tan lleno está y de qué color. */
export function plazo(t: ConPlazo, hoyTexto = hoyIso()): { k: ClavePlazo; pct: number; txt: string } {
  const hoy = dia0(hoyTexto);
  if (t.estado === "terminada") return { k: "h", pct: 100, txt: t.terminada_en ? `Entregada ${corta(String(t.terminada_en).slice(0, 10))}` : "Terminada" };
  if (!t.fecha_compromiso) return { k: "n", pct: 0, txt: "Sin fecha" };
  const fin = dia0(t.fecha_compromiso), ini = Math.min(dia0(String(t.fecha_inicio || t.creada_en || t.fecha_compromiso).slice(0, 10)), fin);
  const pct = Math.max(0, Math.min(100, ((hoy - ini + 1) / (fin - ini + 1)) * 100));
  if (t.estado === "en_revision") return { k: "r", pct, txt: "Pidió revisión" };
  if (hoy > fin) { const n = habiles(fin, hoy); return { k: "c", pct: 100, txt: n ? `Vencida ${n} d` : "Vencida" }; }
  if (hoy === fin) return { k: "a", pct: 100, txt: "Vence hoy" };
  const n = habiles(hoy, fin);
  return { k: n <= 2 ? "a" : "", pct, txt: n === 1 ? "Falta 1 d" : `Faltan ${n} d` };
}

/** En qué tramo de tiempo cae una tarea abierta, como las listas de Trello. */
export type Tramo = "vencidas" | "hoy" | "semana" | "despues" | "sin" | "revision";
export function tramo(t: ConPlazo, hoy = hoyIso()): Tramo {
  if (t.estado === "en_revision") return "revision";
  if (!t.fecha_compromiso) return "sin";
  const dom = new Date((dia0(lunesDe(hoy)) + 6) * 864e5).toISOString().slice(0, 10);
  return t.fecha_compromiso < hoy ? "vencidas" : t.fecha_compromiso === hoy ? "hoy" : t.fecha_compromiso <= dom ? "semana" : "despues";
}
export const TRAMOS: [Tramo, string, string][] = [["vencidas", "Vencidas", "c"], ["hoy", "Para hoy", "a"], ["semana", "Esta semana", ""], ["despues", "Más adelante", ""], ["sin", "Sin fecha", ""], ["revision", "Esperando revisión", ""]];

/** Una semana de carga de una persona, como la devuelve carga_semanal. */
export interface Carga {
  persona_id: string;
  nombre: string;
  semana: string;
  dias_habiles: number | string;
  dias_ocupados: number | string;
  tareas: number;
  sin_estimar: number;
  vencidas: number;
}
export type Capacidad = Pick<Carga, "dias_habiles" | "dias_ocupados">;
export const libres = (c: Capacidad) => Number(c.dias_habiles) - Number(c.dias_ocupados);
export const cargaPorPersona = (filas: Carga[]) => {
  const m = new Map<string, Carga[]>();
  for (const c of filas) (m.get(c.persona_id) || m.set(c.persona_id, []).get(c.persona_id)!).push(c);
  return m;
};
/** La frase de la semana de una persona; «pasada» cuando tiene más de lo que cabe. */
export const leeCarga = (c0: Capacidad): { texto: string; pasada: boolean } => {
  const l = libres(c0);
  if (Number(c0.dias_habiles) === 0) return { texto: "Sin días hábiles en la semana", pasada: false };
  if (l < -0.05) return { texto: `Tiene ${enDias(-l)} más de lo que cabe`, pasada: true };
  if (l < 0.5) return { texto: "Semana llena", pasada: false };
  if (Number(c0.dias_ocupados) === 0) return { texto: "Libre esta semana", pasada: false };
  return { texto: `Le queda${l > 1 ? "n" : ""} ${enDias(l)} esta semana`, pasada: false };
};
/** Lo que le queda a una persona, para decirlo al lado de su nombre. */
export const leeEspacio = (e: number | null) =>
  e == null ? "" : e < -0.05 ? " · pasada esta semana" : e < 0.5 ? " · llena esta semana" : ` · ${enDias(e)} libre${e > 1 ? "s" : ""} esta semana`;

/** Lo que le queda libre a una persona entre el inicio y la entrega: suma las
 *  semanas que toca el tramo y, de una semana tomada a medias, la parte que cae
 *  dentro (por días de lunes a viernes). */
export function tramoLibre(sem: Carga[] | undefined, ini: string, fin: string) {
  const a = dia0(ini), b = dia0(fin);
  let hab = 0, oc = 0, visto = -Infinity;
  for (const s of sem || []) {
    const l = dia0(s.semana), d0 = Math.max(a, l), d1 = Math.min(b, l + 4);
    visto = Math.max(visto, l + 6);
    if (d1 < d0) continue;
    const fr = (d1 - d0 + 1) / 5;
    hab += Number(s.dias_habiles) * fr; oc += Number(s.dias_ocupados) * fr;
  }
  return { dias_habiles: hab, dias_ocupados: oc, libre: hab - oc, fuera: b > visto };
}

export const pct = (a: number, b: number) => (b ? Math.round((a / b) * 100) : 0);

export interface FaseResumen { id: string; estado: string; fecha_compromiso?: string | null; fase: string }
export interface AvanceFase { fase_id: string; tareas: number; terminadas: number; trabajo_terminado?: boolean }

/** El estado de una fase en la tira: cerrada llena, en curso con su avance, vencida en tierra, por abrir solo el borde. */
export const estadoFase = (f: FaseResumen, av: Map<string, AvanceFase> | undefined, hoy = hoyIso()) => {
  const a = av?.get(f.id), p = a?.tareas ? (a.terminadas / a.tareas) * 100 : 0;
  const abierta = f.estado === "en_curso" || f.estado === "en_revision";
  const tarde = abierta && !!f.fecha_compromiso && f.fecha_compromiso < hoy;
  const k = f.estado === "cerrada" ? "cerrada" : tarde ? "tarde" : abierta ? "curso" : "";
  const dice = f.estado === "cerrada" ? "cerrada" : tarde ? "vencida" : abierta ? `en curso, ${p.toFixed(0)} %` : "por abrir";
  return { pct: p, k, abierta, tarde, dice };
};

/** Avance de un conjunto de fases por sus tareas: hechas sobre el total. */
export const avanceTotal = (aa: { tareas: number; terminadas: number }[]) => {
  const tot = aa.reduce((n, a) => n + a.tareas, 0), hechas = aa.reduce((n, a) => n + a.terminadas, 0);
  return { tot, hechas, pct: tot ? (hechas / tot) * 100 : 0 };
};
