"use client";
// Las piezas de la carga por semana que comparten Equipo y el centro de mando:
// las celdas de cada semana y la frase de quién tiene espacio.
import { SEMANAS } from "@/lib/config";
import { fecha } from "@/lib/dominio/fechas";
import { enDias, lista, num } from "@/lib/dominio/texto";
import { libres, type Carga } from "@/lib/dominio/plazo";

/** Una celda por semana: el número es lo que le queda libre, en días; la raya, cuánto ya está ocupado. */
export function CeldasCarga({ sem }: { sem: Carga[] }) {
  return (
    <>
      {sem.map((s) => {
        const x = libres(s), hab = Number(s.dias_habiles), oc = Number(s.dias_ocupados);
        return (
          <span key={s.semana} className={hab === 0 ? "n" : x < -0.05 ? "c" : x < 0.5 ? "a" : ""}
            aria-label={`Semana del ${fecha(s.semana)}: ${hab === 0 ? "sin días hábiles" : x < -0.05 ? "pasada por " + enDias(-x) : enDias(x) + " libres de " + num(hab)}`}>
            <b>{hab === 0 ? "–" : x < -0.05 ? "+" + num(-x) : x < 0.5 ? "0" : num(x)}</b>
            <small>{hab === 0 ? "" : x < -0.05 ? "de más" : x < 0.5 ? "llena" : x <= 1 ? "libre" : "libres"}</small>
            <i style={{ width: `${hab ? Math.min((oc / hab) * 100, 100).toFixed(0) : 0}%` }} />
          </span>
        );
      })}
    </>
  );
}

export interface PersonaCarga { id: string; nombre: string; sem: Carga[] }

/** Quién tiene espacio esta semana (o la que viene) y quién está pasado. */
export function fraseCarga(gente: PersonaCarga[], primera: boolean): string {
  const libre = gente.filter((p) => libres(p.sem[0]) >= 0.5).sort((a, b) => libres(b.sem[0]) - libres(a.sem[0]));
  const pasada = gente.filter((p) => libres(p.sem[0]) < -0.05);
  const cuando = primera ? "Esta semana" : "La semana que viene";
  let f = libre.length ? `${cuando} ${libre.length > 1 ? "tienen" : "tiene"} espacio ${lista(libre.map((p) => `${p.nombre.split(" ")[0]} (${enDias(libres(p.sem[0]))})`))}.`
    : (() => {
      for (let s = 1; s < SEMANAS; s++) {
        const q = gente.filter((p) => p.sem[s] && libres(p.sem[s]) >= 0.5);
        if (q.length) return `${cuando} nadie tiene espacio. ${q.length > 1 ? "Los primeros que se desocupan son" : "El primero que se desocupa es"} ${lista(q.map((p) => p.nombre.split(" ")[0]))}, la semana del ${fecha(q[0].sem[s].semana)}.`;
      }
      return `Nadie tiene espacio en las próximas ${SEMANAS} semanas.`;
    })();
  if (pasada.length) f += ` ${lista(pasada.map((p) => `${p.nombre.split(" ")[0]} (${enDias(-libres(p.sem[0]))})`))} ${pasada.length > 1 ? "tienen" : "tiene"} más trabajo del que cabe.`;
  return f;
}
