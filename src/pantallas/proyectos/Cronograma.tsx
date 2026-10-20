"use client";
// Cronograma: semanas de izquierda a derecha, agrupado por fase, con la línea de hoy.
import Link from "next/link";
import type { CSSProperties } from "react";
import { R } from "@/lib/rutas";
import { corta, dia0, isoDe, lunesDe } from "@/lib/dominio/fechas";
import { iniciales, nFase } from "@/lib/dominio/texto";
import { plazo } from "@/lib/dominio/plazo";
import { Vacio } from "@/componentes/ui/piezas";
import { quienDe, type TareaP, type VistaProps } from "./tipos";

type ConFecha = TareaP & { fecha_compromiso: string };

export function Cronograma({ fases, tareas, hoy: hoyTexto, repartir }: VistaProps) {
  const hoy = dia0(hoyTexto), conFecha = tareas.filter((t): t is ConFecha => !!t.fecha_compromiso);
  if (!conFecha.length) return <><Vacio>Todavía no hay tareas con fecha para dibujar.</Vacio>{repartir}</>;

  const ini = (t: ConFecha) => Math.min(dia0(String(t.fecha_inicio || t.creada_en || t.fecha_compromiso).slice(0, 10)), dia0(t.fecha_compromiso));
  const l0 = dia0(lunesDe(isoDe(Math.min(hoy - 14, ...conFecha.map(ini)))));
  const n = Math.min(Math.ceil((Math.max(hoy + 27, ...conFecha.map((t) => dia0(t.fecha_compromiso))) - l0 + 1) / 7), 16), fin = l0 + n * 7 - 1;
  const total = n * 7, x = (d: number) => ((Math.max(l0, Math.min(d, fin + 1)) - l0) / total) * 100;
  const fase = new Map(fases.map((f) => [f.id, f]));

  const fila = (t: ConFecha) => {
    const p = plazo(t, hoyTexto), a = ini(t), b = Math.max(dia0(t.fecha_compromiso), p.k === "c" ? hoy : 0), izq = x(a), der = 100 - x(b + 1);
    if (b < l0 || a > fin) return null;
    const hecho = t.estado === "terminada" ? 100 : Math.max(0, Math.min(100, ((hoy - a + 1) / (b - a + 1)) * 100));
    return (
      <Link key={t.id} className={`cr-t ${p.k}`} href={R.tarea(t.id)} aria-label={`${t.titulo}: ${p.txt}`}>
        <i style={{ left: `${izq.toFixed(2)}%`, right: `${der.toFixed(2)}%` }}><b style={{ width: `${hecho.toFixed(0)}%` }} /></i>
        <span style={izq > 55 ? { right: `${der.toFixed(2)}%` } : { left: `${izq.toFixed(2)}%` }}>{t.titulo} · {iniciales(quienDe(t))} · {p.k === "h" ? "terminada" : p.txt.toLowerCase()}</span>
      </Link>
    );
  };
  const sinFase: [string, ConFecha[]] = ["Sin fase", conFecha.filter((t) => !fase.has(t.fase_id ?? ""))];
  const grupos = [...fases.map((f): [string, ConFecha[]] => [nFase(f.fase), conFecha.filter((t) => t.fase_id === f.id)]), sinFase].filter(([, l]) => l.length);
  return (
    <>
      <div className="cr" style={{ "--n": n } as CSSProperties} tabIndex={0} role="group" aria-label="Cronograma del proyecto">
        <div className="cr-in">
          <div className="cr-sems">
            {Array.from({ length: n }, (_, i) => { const s = isoDe(l0 + i * 7); return <span key={s}>{s === lunesDe(hoyTexto) ? "Esta" : corta(s)}</span>; })}
          </div>
          <div className="cr-fondo">{Array.from({ length: n }, (_, i) => <span key={i} />)}</div>
          {hoy >= l0 && hoy <= fin ? <div className="cr-hoy" style={{ left: `${x(hoy + 0.5).toFixed(2)}%` }} /> : null}
          {grupos.map(([g, l]) => (
            <div key={g}>
              <div className="cr-g"><span>{g}</span></div>
              {l.map(fila)}
            </div>
          ))}
        </div>
      </div>
      <div className="cr-ley">
        <span><i style={{ background: "var(--tinta)" }} />Lo que ya pasó</span>
        <span><i style={{ background: "var(--alerta)" }} />Por vencer</span>
        <span><i style={{ background: "var(--critico)" }} />Vencida, hasta hoy</span>
        <span><i style={{ background: "var(--ok)" }} />Terminada</span>
      </div>
      {repartir}
    </>
  );
}
