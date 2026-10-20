"use client";
// Lo que le queda libre a la persona escogida entre el inicio y la entrega, y
// cómo le queda la semana con esta tarea encima.
import { fecha } from "@/lib/dominio/fechas";
import { enDias } from "@/lib/dominio/texto";
import { tramoLibre } from "@/lib/dominio/plazo";
import { BarraCapacidad } from "@/componentes/ui/piezas";
import type { Reparto } from "./revision";

export type { Reparto } from "./revision";

export function Pista({ reparto, quien, inicio, entrega, dias }: { reparto: Reparto; quien: string; inicio: string; entrega: string; dias: string }) {
  const pide = Number(dias) || 0, sem = reparto.porPersona.get(quien), nombre = (reparto.opciones.find((o) => o[0] === quien) || [])[1] || "";
  if (!quien || !sem || !inicio || !entrega || !pide || inicio > entrega) return <p className="pista" aria-live="polite" />;
  const t = tramoLibre(sem, inicio, entrega), queda = t.libre - pide, cuando = inicio === entrega ? `el ${fecha(inicio)}` : `entre el ${fecha(inicio)} y el ${fecha(entrega)}`;
  const libreTxt = t.libre < 0.05 ? "el tramo lleno" : `${enDias(t.libre)} libre${t.libre > 1 ? "s" : ""}`;
  return (
    <p className="pista" aria-live="polite">
      <BarraCapacidad c={t} extra={pide} />
      {t.dias_habiles < 0.05 ? `${nombre} no tiene días hábiles ${cuando}.`
        : queda < -0.05 ? <em>{nombre} tiene {libreTxt} {cuando} y la tarea pide {enDias(pide)}: queda pasada por {enDias(-queda)}.</em>
        : <>{nombre} tiene {libreTxt} {cuando}, de {enDias(t.dias_habiles)} hábiles. {queda < 0.05 ? "Con esta tarea queda llena." : `Con esta tarea le queda${queda > 1 ? "n" : ""} ${enDias(queda)}.`}</>}
      {t.fuera ? " La entrega cae más allá de las semanas que se alcanzan a ver: el cálculo llega hasta donde hay datos." : ""}
    </p>
  );
}
